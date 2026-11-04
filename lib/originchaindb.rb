# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'ipaddr'
require 'securerandom'
require_relative 'originchaindb/version'
require_relative 'originchaindb/sql_result'
require_relative 'originchaindb/fts_result'
require_relative 'originchaindb/vector_hit'
require_relative 'originchaindb/resources'
require_relative 'originchaindb/integration'

module OriginChainDB
  # Error messages omit credentials and server data. Diagnostics are opt-in.
  class Error < StandardError
    attr_reader :kind, :status, :body, :request_id, :retry_after, :result
    def initialize(kind, status: nil, body: nil, request_id: nil, retry_after: nil, result: nil)
      @kind, @status, @body, @request_id, @retry_after, @result = kind, status, body, request_id, retry_after, result
      super("OriginChainDB #{kind} error#{status ? " (HTTP #{status})" : ''}")
    end
  end

  # Reuses one persistent connection, serialized by a mutex. Use separate clients
  # for parallel requests. No request is replayed automatically.
  class Client
    attr_reader :sql, :rows, :schemas, :vector, :fts, :graph
    def initialize(url:, token:, timeout: 60, on_request: nil, http: nil)
      @url = URI.parse(url)
      loopback = @url.hostname == 'localhost' || (IPAddr.new(@url.hostname).loopback? rescue false)
      if !@url.host || @url.userinfo || @url.query || @url.fragment || url.match?(/[\x00-\x20\x7f\\]/) ||
         !(@url.scheme == 'https' || (@url.scheme == 'http' && loopback))
        raise ArgumentError, 'Use the HTTPS database URL copied from Connect; HTTP is only allowed on loopback'
      end
      raise ArgumentError, 'Token must be printable ASCII or a callable provider' unless token.respond_to?(:call) || valid_token?(token)
      raise ArgumentError, 'on_request must be callable' unless on_request.nil? || on_request.respond_to?(:call)
      raise ArgumentError, 'Timeout must be finite and positive' unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
      @token, @timeout, @mutex, @closed = token, timeout, Mutex.new, false
      @observer = on_request
      @url.path = @url.path.sub(%r{/+\z}, '')
      if http && (!http.is_a?(Net::HTTP) || http.started? || http.address != @url.hostname || http.port != @url.port)
        raise ArgumentError, 'Injected HTTP connection must be unstarted and target the database host and port'
      end
      @http = http || Net::HTTP.new(@url.hostname, @url.port)
      @http.use_ssl = @url.scheme == 'https'
      @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      @http.verify_hostname = true
      @http.open_timeout = [timeout, 10].min
      @http.read_timeout = timeout
      @http.write_timeout = timeout
      @http.max_retries = 0
      @sql, @rows, @schemas = Sql.new(self), Rows.new(self), Schemas.new(self)
      @vector, @fts, @graph = Vector.new(self), Fts.new(self), Graph.new(self)
    rescue URI::InvalidURIError
      raise ArgumentError, 'Invalid database URL', cause: nil
    end

    def self.from_env(**options)
      new(url: ENV.fetch('OC_URL'), **{ token: ENV['OC_TOKEN'] }.merge(options))
    end

    def self.open(**options)
      client = new(**options)
      return client unless block_given?
      begin
        yield client
      ensure
        client.close
      end
    end

    def inspect = '#<OriginChainDB::Client>'
    alias to_s inspect

    def close
      @mutex.synchronize do
        @http.finish if @http.started?
        @closed = true
      end
    end

    def usage = request('GET', 'usage')
    def query_metrics(minutes: 60, bucket_seconds: 60)
      request('GET', 'query-metrics', query: { minutes: minutes, bucket_seconds: bucket_seconds })
    end

    # Internal transport. Call the operation namespaces in application code.
    def request(method, path, body: nil, query: {}, text: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      observed = {}
      kind = 'canceled'
      begin
        result = request_core(method, path, body: body, query: query, text: text, observed: observed)
        kind = nil
        result
      rescue StandardError => error
        kind = error.is_a?(Error) ? error.kind : 'client'
        raise
      ensure
        if @observer
          first = path.split('/', 2).first
          operation = %w[sql rows schemas vector fts graph cypher usage query-metrics].include?(first) ? first : 'other'
          event = RequestEvent.new(method: method, operation: operation,
            duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
            status: observed[:status], request_id: observed[:request_id], error_kind: kind).freeze
          begin
            @observer.call(event)
          rescue StandardError
            # Local observation never changes a database result.
          end
        end
      end
    end

    private

    def valid_token?(value) = value.is_a?(String) && value.match?(/\A[\x21-\x7e]+\z/)

    def request_core(method, path, body:, query:, text:, observed:)
      @mutex.synchronize do
        raise IOError, 'Client is closed' if @closed
        token = @token
        if token.respond_to?(:call)
          begin
            token = token.call
            raise ArgumentError unless valid_token?(token)
          rescue StandardError
            raise Error.new('credential'), cause: nil
          end
        end
        target = "#{@url.path}/#{path}"
        target += "?#{URI.encode_www_form(query)}" unless query.empty?
        headers = { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json',
                    'User-Agent' => "originchaindb-ruby/#{VERSION}", 'X-OC-Logical-Request-Id' => SecureRandom.hex(16) }
        payload = text || (body.nil? ? nil : JSON.generate(body))
        headers['Content-Type'] = text ? 'text/plain' : 'application/json' unless payload.nil?
        req = Net::HTTPGenericRequest.new(method, !payload.nil?, true, target, headers)
        req.body = payload unless payload.nil?
        @http.start unless @http.started?
        raw = +''
        response = @http.request(req) do |res|
          observed[:status], observed[:request_id] = res.code.to_i, res['x-oc-request-id']
          res.read_body do |chunk|
            raise Error.new('protocol', status: res.code.to_i) if raw.bytesize + chunk.bytesize > 33_554_432
            raw << chunk
          end
        end
        status = response.code.to_i
        begin
          value = raw.empty? ? nil : JSON.parse(raw)
        rescue JSON::ParserError
          raise Error.new('protocol', status: status) if (200...300).cover?(status) && !response['content-type'].to_s.start_with?('text/')
          value = raw
        end
        unless (200...300).cover?(status)
          kind = { 401 => 'authentication', 403 => 'permission', 429 => 'rate_limit' }.fetch(status, 'http')
          raise Error.new(kind, status: status, body: value, request_id: response['x-oc-request-id'], retry_after: response['retry-after'])
        end
        value
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        @http.finish if @http.started?
        raise Error.new('timeout'), cause: nil
      rescue SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError
        @http.finish if @http.started?
        raise Error.new('transport'), cause: nil
      end
    end
  end
end

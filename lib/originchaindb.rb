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
    def initialize(url:, token:, timeout: 60)
      @url = URI.parse(url)
      loopback = @url.hostname == 'localhost' || (IPAddr.new(@url.hostname).loopback? rescue false)
      if !@url.host || @url.userinfo || @url.query || @url.fragment || url.match?(/[\x00-\x20\x7f\\]/) ||
         !(@url.scheme == 'https' || (@url.scheme == 'http' && loopback))
        raise ArgumentError, 'Use the HTTPS database URL copied from Connect; HTTP is only allowed on loopback'
      end
      raise ArgumentError, 'Token must be nonempty printable ASCII without spaces' unless token.is_a?(String) && token.match?(/\A[\x21-\x7e]+\z/)
      raise ArgumentError, 'Timeout must be finite and positive' unless timeout.is_a?(Numeric) && timeout.finite? && timeout.positive?
      @token, @timeout, @mutex, @closed = token, timeout, Mutex.new, false
      @url.path = @url.path.sub(%r{/+\z}, '')
      @http = Net::HTTP.new(@url.hostname, @url.port)
      @http.use_ssl = @url.scheme == 'https'
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
      new(url: ENV.fetch('OC_URL'), token: ENV.fetch('OC_TOKEN'), **options)
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
      @mutex.synchronize do
        raise IOError, 'Client is closed' if @closed
        target = "#{@url.path}/#{path}"
        target += "?#{URI.encode_www_form(query)}" unless query.empty?
        headers = { 'Authorization' => "Bearer #{@token}", 'Accept' => 'application/json',
                    'User-Agent' => "originchaindb-ruby/#{VERSION}", 'X-OC-Logical-Request-Id' => SecureRandom.hex(16) }
        payload = text || (body.nil? ? nil : JSON.generate(body))
        headers['Content-Type'] = text ? 'text/plain' : 'application/json' unless payload.nil?
        req = Net::HTTPGenericRequest.new(method, !payload.nil?, true, target, headers)
        req.body = payload unless payload.nil?
        @http.start unless @http.started?
        raw = +''
        response = @http.request(req) do |res|
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

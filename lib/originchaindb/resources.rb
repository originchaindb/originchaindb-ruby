# frozen_string_literal: true
module OriginChainDB
  class Resource
    def initialize(client) = @client = client
    private
    def path(*parts)
      parts.map do |name|
        raise ArgumentError, 'Invalid path name' unless name.is_a?(String) && !name.empty? && !['.', '..'].include?(name) && !name.match?(/[\x00-\x1f\x7f]/)
        URI.encode_www_form_component(name).gsub('+', '%20')
      end.join('/')
    end
    def embedding!(values)
      raise ArgumentError, 'Vector must contain finite numbers' unless values.is_a?(Array) && !values.empty? && values.all? { |v| v.is_a?(Numeric) && v.finite? }
    end
  end

  class Sql < Resource
    def run(statement, params: [])
      raise ArgumentError, 'SQL statement must not be empty' unless statement.is_a?(String) && !statement.strip.empty?
      raise ArgumentError, 'SQL parameters must be an array' unless params.is_a?(Array)
      result = SqlResult.new(@client.request('POST', 'sql', body: { sql: statement, params: params }))
      raise Error.new('batch', status: 200, result: result) if result.failed?
      result
    end
    alias execute run
    def query(statement, params: [])
      result = run(statement, params: params)
      raise Error.new('protocol') unless result.kind == 'select'
      result
    end
  end

  class Schemas < Resource
    def list = @client.request('GET', 'schemas')
    def get(name) = @client.request('GET', path('schemas', name))
    def register(toml) = @client.request('POST', 'schemas', text: toml)
  end
  class Rows < Resource
    def get(schema, key) = @client.request('GET', path('rows', schema, key))
    def put(schema, row)
      raise ArgumentError, 'Row must be a hash' unless row.is_a?(Hash)
      @client.request('POST', path('rows', schema), body: row)
    end
    def put_batch(schema, rows)
      raise ArgumentError, 'Rows must be an array of hashes' unless rows.is_a?(Array) && rows.all? { |r| r.is_a?(Hash) }
      @client.request('POST', path('rows', schema, '_batch'), body: rows)
    end
  end
  class Vector < Resource
    def put(table, id, embedding, metadata: nil)
      embedding!(embedding)
      body = { id: id, embedding: embedding, dim: embedding.length }
      body[:metadata] = metadata unless metadata.nil?
      @client.request('POST', path('vector', table, 'put'), body: body)
    end
    def search(table, query, k: 10, metric: 'cosine', filter: nil)
      embedding!(query)
      raise ArgumentError, 'k must be a positive integer' unless k.is_a?(Integer) && k.positive?
      body = { query: query, dim: query.length, k: k, metric: metric }
      body[:filter] = filter unless filter.nil?
      VectorHit.decode(@client.request('POST', path('vector', table, 'topk'), body: body))
    end
    def delete(table, id) = @client.request('DELETE', path('vector', table, id))
  end
  class Fts < Resource
    def index(table, field, id, text) = @client.request('POST', path('fts', table, field), body: { doc_id: id, text: text })
    def search(table, field, query, mode: 'bm25', k: 10, highlight: false, fuzzy: nil, facets: nil)
      raise ArgumentError, 'Invalid search mode or k' unless %w[bm25 boolean phrase].include?(mode) && k.is_a?(Integer) && k.positive?
      params = { q: query, mode: mode }
      params[:k] = k if mode == 'bm25'
      params[:highlight] = 'true' if highlight
      params[:fuzzy] = fuzzy unless fuzzy.nil?
      params[:facets] = facets.join(',') unless facets.nil?
      FtsResult.new(@client.request('GET', path('fts', table, field), query: params))
    end
  end
  class Graph < Resource
    def query(cypher, params: {})
      raise ArgumentError, 'Cypher parameters must be a hash' unless params.is_a?(Hash)
      @client.request('POST', 'cypher', body: { cypher: cypher, params: params })
    end
    def neighbors(schema, key, relation) = @client.request('GET', path('graph', schema, 'neighbors'), query: { pk: key, rel: relation })
    def bfs(schema, key, relation, max_depth: 5)
      raise ArgumentError, 'max_depth must be positive' unless max_depth.is_a?(Integer) && max_depth.positive?
      @client.request('GET', path('graph', schema, 'bfs'), query: { pk: key, rel: relation, max_depth: max_depth })
    end
  end
end

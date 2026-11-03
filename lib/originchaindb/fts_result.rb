# frozen_string_literal: true
module OriginChainDB
  # Ranked, boolean and phrase searches share this result structure.
  class FtsResult
    Hit = Data.define(:doc_id, :score, :highlights, :raw)
    attr_reader :hits, :facets, :raw
    def initialize(value)
      @raw = value
      @facets = value.is_a?(Hash) ? value['facets'] : nil
      items = value.is_a?(Hash) ? value['hits'] : value
      raise Error.new('protocol') unless items.is_a?(Array)
      @hits = items.map do |item|
        if item.is_a?(String)
          Hit.new(doc_id: item, score: 0.0, highlights: nil, raw: nil)
        else
          unless item.is_a?(Hash) && item['doc_id'].is_a?(String) &&
                 (!item.key?('score') || (item['score'].is_a?(Numeric) && item['score'].finite?))
            raise Error.new('protocol')
          end
          Hit.new(doc_id: item['doc_id'], score: item.fetch('score', 0.0), highlights: item['highlights'], raw: item)
        end
      end.freeze
    end
  end
end

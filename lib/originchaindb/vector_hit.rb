# frozen_string_literal: true
module OriginChainDB
  VectorHit = Data.define(:id, :score, :metadata, :raw) do
    def self.decode(value)
      raise Error.new('protocol') unless value.is_a?(Array)
      value.map do |item|
        raise Error.new('protocol') unless item.is_a?(Hash)
        id, score = item['id'] || item['vec_id'], item['score']
        unless id.is_a?(String) && score.is_a?(Numeric) && score.finite?
          raise Error.new('protocol')
        end
        new(id: id, score: score, metadata: item['metadata'], raw: item)
      end
    end
  end
end

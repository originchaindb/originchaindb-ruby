# frozen_string_literal: true

module OriginChainDB
  # Local transport metadata. Duration is seconds. Contains no URLs, table names,
  # SQL, parameters, bodies or credentials. HTTP success can precede a result
  # decoding failure. Observer callbacks run outside the connection mutex.
  RequestEvent = Struct.new(:method, :operation, :duration, :status, :request_id, :error_kind, keyword_init: true)

  # Zero-based row that failed conversion; inspect cause for the native error.
  class RowDecodeError < StandardError
    attr_reader :row
    def initialize(row)
      @row = row
      super("Cannot decode SQL row #{row}")
    end
  end
end

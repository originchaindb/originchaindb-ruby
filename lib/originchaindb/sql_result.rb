# frozen_string_literal: true
module OriginChainDB
  # Unknown fields and arbitrary-precision Ruby integers are retained in raw.
  class SqlResult
    attr_reader :kind, :rows, :columns, :column_types, :rows_affected, :rows_buffered, :results, :stopped_on_error, :raw
    def initialize(value)
      raise Error.new('protocol') unless value.is_a?(Hash) && value['kind'].is_a?(String)
      @raw, @kind = value, value['kind']
      @rows, children = value.fetch('rows', []), value.fetch('results', [])
      @columns, @column_types = value['columns'] || value['returning'], value['column_types']
      @stopped_on_error = value.fetch('stopped_on_error', false)
      unless @rows.is_a?(Array) && @rows.all? { |r| r.is_a?(Hash) } && children.is_a?(Array) &&
             [true, false].include?(@stopped_on_error) && (@columns.nil? || (@columns.is_a?(Array) && @columns.all? { |c| c.is_a?(String) }))
        raise Error.new('protocol')
      end
      @rows_affected = count(value['rows_affected'] || (@kind == 'insert' ? value['inserted'] : @kind == 'select' ? 0 : nil))
      @rows_buffered = count(value['rows_buffered'])
      @results = children.map do |child|
        child = child.merge('kind' => 'error') if child.is_a?(Hash) && child.key?('error') && !child.key?('kind')
        SqlResult.new(child)
      end
    end

    def failed? = @stopped_on_error || @kind == 'error' || @raw.key?('error') || @results.any?(&:failed?)

    # Map independent row copies through an application constructor or validator.
    # No partial list is returned if any row fails to map.
    def map_rows
      raise ArgumentError, 'Provide a row decoder block' unless block_given?
      @rows.each_with_index.map do |row, index|
        begin
          yield copy_value(row)
        rescue StandardError => error
          raise RowDecodeError.new(index), cause: error
        end
      end
    end

    private
    def copy_value(value)
      case value
      when Hash then value.transform_values { |item| copy_value(item) }
      when Array then value.map { |item| copy_value(item) }
      when String then value.dup
      else value
      end
    end
    def count(value)
      raise Error.new('protocol') unless value.nil? || (value.is_a?(Integer) && value >= 0)
      value
    end
  end
end

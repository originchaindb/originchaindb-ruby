# frozen_string_literal: true
module OriginChainDB
  BatchResult = Data.define(:offset, :count, :inserted)
  RowPage = Data.define(:rows, :next_cursor)
  class IterationCancelled < StandardError; end
  class BatchWriteError < StandardError
    attr_reader :offset, :count, :outcome
    def initialize(offset, count, outcome)
      @offset, @count, @outcome = offset, count, outcome
      super("Batch at input offset #{offset} failed (#{outcome})")
    end
  end

  class Rows
    # Lazy acknowledged ranges. A request failure has an unknown outcome and is never replayed.
    def write_batches(schema, rows, batch_size: 1000, max_bytes: 1_048_576, cancelled: nil)
      Enumerator.new do |output|
        unless batch_size.is_a?(Integer) && (1..10_000).cover?(batch_size) && max_bytes.is_a?(Integer) && (2..8_388_608).cover?(max_bytes)
          raise ArgumentError, 'Invalid batch bounds'
        end
        path('rows', schema, '_batch')
        batch, size, offset = [], 2, 0
        check = -> { raise IterationCancelled, 'Iteration canceled' if cancelled&.call }
        flush = lambda do
          check.call
          begin
            value = put_batch(schema, batch)
            inserted = value.is_a?(Hash) ? value['inserted'] : nil
            raise Error.new('protocol') unless inserted.is_a?(Integer) && (0..batch.length).cover?(inserted)
            BatchResult.new(offset: offset, count: batch.length, inserted: inserted)
          rescue StandardError => error
            raise BatchWriteError.new(offset, batch.length, 'unknown'), cause: error
          end
        end
        input = rows.to_enum
        loop do
          check.call
          begin
            item = input.next
          rescue StopIteration
            break
          rescue StandardError => error
            raise BatchWriteError.new(offset, batch.length, 'not_sent'), cause: error
          end
          begin
            raise ArgumentError, 'Each row must be a hash' unless item.is_a?(Hash)
            text = JSON.generate(item)
            row = JSON.parse(text)
            raise ArgumentError, 'Row exceeds max_bytes' if text.bytesize + 2 > max_bytes
          rescue StandardError => error
            raise BatchWriteError.new(offset, batch.length + 1, 'not_sent'), cause: error
          end
          if !batch.empty? && size + 1 + text.bytesize > max_bytes
            result = flush.call
            offset += batch.length
            batch, size = [], 2
            output << result
          end
          size += text.bytesize + (batch.empty? ? 0 : 1)
          batch << row
          if batch.length == batch_size
            result = flush.call
            offset += batch.length
            batch, size = [], 2
            output << result
          end
        end
        output << flush.call unless batch.empty?
      end
    end

    # The key must be a unique immutable non-null string column with binary ordering.
    def pages(schema, key, page_size: 1000, after: nil, cancelled: nil)
      Enumerator.new do |output|
        parts = schema.split('.', -1)
        unless (1..2).cover?(parts.length) && [*parts, key].all? { |name| name.is_a?(String) && name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) } && page_size.is_a?(Integer) && (1..10_000).cover?(page_size) && (after.nil? || after.is_a?(String))
          raise ArgumentError, 'Invalid page options'
        end
        table = parts.map { |part| %Q{"#{part}"} }.join('.')
        cursor = after&.dup
        loop do
          raise IterationCancelled, 'Iteration canceled' if cancelled&.call
          sql = "SELECT * FROM #{table}" + (cursor.nil? ? '' : %Q{ WHERE "#{key}" > $1}) + %Q{ ORDER BY "#{key}" ASC LIMIT #{page_size}}
          rows = @client.sql.query(sql, params: cursor.nil? ? [] : [cursor]).rows
          raise Error.new('protocol') if rows.length > page_size
          last = cursor
          rows.each do |row|
            value = row[key]
            raise Error.new('protocol') unless value.is_a?(String) && (last.nil? || value.b > last.b)
            last = value
          end
          break if rows.empty?
          cursor = rows.length < page_size ? nil : last.dup.freeze
          output << RowPage.new(rows: rows, next_cursor: cursor)
          break if cursor.nil?
        end
      end
    end

    def scan(schema, key, **options)
      Enumerator.new do |output|
        pages(schema, key, **options).each do |page|
          page.rows.each do |row|
            raise IterationCancelled, 'Iteration canceled' if options[:cancelled]&.call
            output << row
          end
        end
      end
    end
  end
end

# frozen_string_literal: true
require_relative '../lib/originchaindb'
def check(value) = (raise 'Iteration assertion failed' unless value)
def source(consumed)
  Enumerator.new do |out|
    row = {}
    'abcde'.each_char { |id| consumed << id; row['id'] = id; out << row }
  end
end
db = OriginChainDB::Client.from_env
consumed = []
batches = db.rows.write_batches('bulk.ok', source(consumed), batch_size: 2)
check(consumed.empty?)
first = batches.next
check(consumed == %w[a b] && [first.offset, first.count, first.inserted] == [0, 2, 2])
check(batches.next.offset == 2)
last = batches.next
check(last.offset == 4 && last.count == 1)
begin batches.next; raise 'Expected end'; rescue StopIteration; end
{'fail' => [2, 4], 'lost' => [0, 2], 'unknown' => [0, 2]}.each do |name, (offset, count)|
  consumed = []
  begin
    db.rows.write_batches("bulk.#{name}", source(consumed), batch_size: 2).to_a
    raise 'Expected failure'
  rescue OriginChainDB::BatchWriteError => error
    check(error.offset == offset && error.count == 2 && error.outcome == 'unknown' && error.cause && consumed.length == count)
  end
end
reports = db.rows.write_batches('bulk.bytes', 'abc'.chars.map { |id| {id: id, value: 'x' * 20} }, max_bytes: 64).to_a
check(reports.map(&:count) == [1, 1, 1])
consumed = []
db.rows.write_batches('bulk.stop', source(consumed), batch_size: 2).each { break }
check(consumed.length == 2)
check(db.rows.write_batches('bulk.never', []).to_a.empty?)
begin db.rows.write_batches('bulk.never', [{id: 'large'}], max_bytes: 4).next; raise 'Expected failure'
rescue OriginChainDB::BatchWriteError => error; check(error.offset == 0 && error.outcome == 'not_sent'); end
begin db.rows.write_batches('bulk.never', [], batch_size: 0).next; raise 'Expected failure'; rescue ArgumentError; end
begin db.rows.write_batches('bulk.never', source([]), cancelled: -> { true }).next; raise 'Expected failure'; rescue OriginChainDB::IterationCancelled; end
check(db.rows.scan('scan.items', 'id', page_size: 2).map { |row| row['id'] } == 'abcde'.chars)
db.rows.scan('scan.stop', 'id', page_size: 2).each { |row| check(row['id'] == 'a'); break }
check(db.rows.pages('scan.resume', 'id', page_size: 2, after: 'b').map(&:next_cursor) == ['d', nil])
%w[bad numeric oversize].each do |name|
  begin db.rows.pages("scan.#{name}", 'id', page_size: 2).next; raise 'Expected failure'
  rescue OriginChainDB::Error => error; check(error.kind == 'protocol'); end
end
check(db.rows.scan('scan.empty', 'id', page_size: 2).to_a.empty?)
begin db.rows.scan('scan.items;DELETE', 'id').next; raise 'Expected failure'; rescue ArgumentError; end
db.close
puts 'Ruby iteration assertions passed'

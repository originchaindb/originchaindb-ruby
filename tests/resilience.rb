require_relative '../lib/originchaindb'

def check(value) = (raise('Resilience assertion failed') unless value)
def fails
  begin
    yield
  rescue OriginChainDB::Error => error
    return error
  end
  raise 'Expected SDK failure'
end
url, token = ENV.fetch('OC_URL'), ENV.fetch('OC_TOKEN')
c = OriginChainDB::Client.new(url: url, token: token)
{ 'expired'=>401, 'revoked'=>401, 'forbidden'=>403, 'limited'=>429 }.each do |name, status|
  error = fails { c.sql.run("fault:#{name}") }
  check(error.status == status && error.request_id == '84f92822-5837-432e-981a-7b24ad65e16c')
  check(error.retry_after == '2') if name == 'limited'
end
fails { c.sql.run('fault:interrupted') }
c.close
slow = OriginChainDB::Client.new(url: url, token: token, timeout: 0.15)
check(fails { slow.sql.run('fault:timeout') }.kind == 'timeout')
slow.close
calls, events = 0, []
c = OriginChainDB::Client.new(url: url, token: -> { "rotate-#{calls += 1}" }, on_request: ->(event) { events << event })
check(fails { c.sql.run('fault:rotate') }.status == 401 && calls == 1)
result = c.sql.run('fault:rotate')
c.close
check(calls == 2 && events.map(&:error_kind) == ['authentication', nil])
check(events.last.operation == 'sql' && events.last.duration > 0)
check(!events.inspect.include?('rotate-') && !events.inspect.include?(url))
Product = Struct.new(:id, :amount, keyword_init: true)
products = result.map_rows { |row| Product.new(id: row.fetch('id'), amount: row.fetch('amount')) }
check(products.first.id == 9_007_199_254_740_993 && products.first.amount == '1.00000000000000001')
result.map_rows { |row| row['amount'].replace('changed') }
check(result.rows.first['amount'] == '1.00000000000000001')
begin
  result.map_rows { |row| Integer(row.fetch('amount')) }
  raise 'Invalid mapping accepted'
rescue OriginChainDB::RowDecodeError => error
  check(error.row == 0)
end
invalid = OriginChainDB::Client.new(url: url, token: -> { "bad\nheader" })
check(fails { invalid.sql.run('fault:invalid-provider') }.kind == 'credential')
invalid.close
observed = OriginChainDB::Client.new(url: url, token: token, on_request: ->(_event) { raise 'observer' })
check(observed.sql.run('fault:observer').rows.length == 1)
observed.close
puts 'Ruby resilience assertions passed'

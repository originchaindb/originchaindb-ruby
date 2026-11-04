# frozen_string_literal: true
# Private integration worker. Credentials arrive over stdin and are never logged.
require_relative '../lib/originchaindb'
$stdout.sync = true
def check(value) = (raise 'Engine compatibility assertion failed' unless value)
current, calls = 'unset', 0
db = OriginChainDB::Client.new(url: ENV.fetch('OC_URL'), token: -> { calls += 1; current })
begin
  $stdin.each_line do |line|
    cmd = JSON.parse(line)
    current = cmd.fetch('token')
    before, status = calls, 200
    begin
      case cmd.fetch('action')
      when 'query'
        result = db.sql.run(cmd.fetch('sql'), params: cmd.fetch('params', []))
        check(cmd['status'] == 200 && result.rows.length == cmd.fetch('rows', 0))
      when 'bulk'
        input = 'abcde'.chars.each_with_index.map { |id,value| {id: id,value: value} }
        reports = db.rows.write_batches(cmd.fetch('schema'),input,batch_size:2).to_a
        check(reports.map { |b| [b.offset,b.count,b.inserted] } == [[0,2,2],[2,2,2],[4,1,1]])
      when 'scan'
        check(db.rows.scan(cmd.fetch('schema'),'id',page_size:2).map { |row| row['id'] } == 'abcde'.chars)
      else
        raise 'Unknown compatibility action'
      end
    rescue OriginChainDB::Error => error
      status = error.status
      check(cmd['status'] != 200 && status == cmd['status'])
    end
    check(calls - before == cmd['requests'])
    puts JSON.generate(ok: true,status: status,requests: calls-before)
  end
ensure
  db.close
end

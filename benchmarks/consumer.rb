# frozen_string_literal: true
require_relative '../lib/originchaindb'
def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def query(client, mode)
  start = now
  result = client.sql.query("bench:#{mode}")
  raise 'Unexpected result size' unless result.rows.length == (mode == 'large' ? 2048 : 1)
  (now - start) * 1000
end
client = OriginChainDB::Client.from_env
report = {}
begin
  10.times { query(client, 'warm') }
  [['sequential',100],['concurrent',64],['large',10]].each do |mode,count|
    start = now
    values = if mode == 'concurrent'
      # Net::HTTP serializes one connection. Each worker owns and closes its client.
      8.times.map do
        Thread.new do
          worker = OriginChainDB::Client.from_env
          begin
            Array.new(count / 8) { query(worker, mode) }
          ensure
            worker.close
          end
        end
      end.flat_map(&:value)
    else
      Array.new(count) { query(client, mode) }
    end
    report[mode + '_ms'] = values
    report[mode + '_rps'] = count / (now - start)
  end
ensure
  client.close
end
puts 'OC_BENCHMARK ' + JSON.generate(report)

require 'originchaindb'

db = OriginChainDB::Client.from_env
begin
  result = db.sql.run('SELECT $1 AS value', params: [7])
  puts result.rows
ensure
  db.close
end

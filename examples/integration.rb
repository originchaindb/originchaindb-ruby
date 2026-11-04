require_relative '../lib/originchaindb'

Product = Struct.new(:id, :name, keyword_init: true)
address = URI(ENV.fetch('OC_URL'))
http = Net::HTTP.new(address.hostname, address.port)
# Configure http.ca_file or construct a proxied Net::HTTP when required.
# The SDK owns this connection and closes it on Client#close.
client = OriginChainDB::Client.new(url: address.to_s,
  token: -> { ENV.fetch('OC_TOKEN') }, http: http,
  on_request: ->(event) { puts "#{event.operation} #{event.status} #{event.duration}s" })
begin
  result = client.sql.run('SELECT $1 AS id, $2 AS name', params: ['p1', 'Widget'])
  products = result.map_rows do |row|
    raise TypeError, 'Product requires string id and name' unless row['id'].is_a?(String) && row['name'].is_a?(String)
    Product.new(id: row['id'], name: row['name'])
  end
  puts products
ensure
  client.close
end

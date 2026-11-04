# frozen_string_literal: true
# Run against a development database; writes sdk_iteration.items.
require_relative '../lib/originchaindb'

db = OriginChainDB::Client.from_env
begin
  schema = 'sdk_iteration.items'
  db.schemas.register(File.read(File.join(__dir__, 'items.toml')))
  rows = Enumerator.new do |output|
    'abcde'.each_char { |id| output << { id: id, name: "Item #{id}" } }
  end
  # section:bulk
  db.rows.write_batches(schema, rows, batch_size: 2).each do |batch|
    puts "#{batch.offset} #{batch.count} #{batch.inserted}"
  end
  # endsection
  # section:scan
  db.rows.scan(schema, 'id', page_size: 2).each do |row|
    puts "#{row['id']} #{row['name']}"
  end
  # endsection
  # Save a checkpoint only after successfully processing the complete page.
  db.rows.pages(schema, 'id', page_size: 2, after: 'b').each do |page|
    page.rows.each { |row| puts "resumed #{row['id']}" }
    puts "next cursor #{page.next_cursor || 'complete'}"
  end
ensure
  db.close
end

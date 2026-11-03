# frozen_string_literal: true
require_relative '../lib/originchaindb'

db = OriginChainDB::Client.from_env
begin
  # section:setup
  schema = 'sdk_examples.products'
  db.schemas.register(File.read(File.join(__dir__, 'products.toml')))
  # endsection

  # section:rows
  db.rows.put(schema, { id: 'p2', name: 'Gadget', description: 'A red gadget' })
  db.rows.put(schema, {
    id: 'p1', name: 'Widget', description: 'A small blue widget', related_to: 'p2'
  })
  product = db.rows.get(schema, 'p1')
  puts product
  # endsection

  # section:sql
  result = db.sql.run('SELECT id, name FROM sdk_examples.products WHERE id = $1', params: ['p1'])
  result.rows.each { |row| puts "#{row['id']} #{row['name']}" }
  # endsection

  # section:vector
  embedding = [0.1, 0.2, 0.3, 0.4]
  db.vector.put(schema, 'p1', embedding, metadata: { category: 'tools' })
  hits = db.vector.search(schema, embedding, k: 5)
  hits.each { |hit| puts "#{hit.id} #{hit.score}" }
  # endsection

  # section:fts
  db.fts.index(schema, 'description', 'p1', 'A small blue widget')
  matches = db.fts.search(schema, 'description', 'blue widget', k: 5)
  matches.hits.each { |hit| puts "#{hit.doc_id} #{hit.score}" }
  # endsection

  # section:graph
  neighbors = db.graph.neighbors(schema, 'p1', 'related')
  puts neighbors
  # endsection
rescue OriginChainDB::Error => error
  warn "Request failed: #{error.kind}, HTTP #{error.status}, request ID #{error.request_id}"
  raise
ensure
  db.close
end

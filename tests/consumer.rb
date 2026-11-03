require_relative '../lib/originchaindb'
def check(value)
  raise 'Contract assertion failed' unless value
end
c = OriginChainDB::Client.from_env
r = c.sql.run('contract:select', params: [7, "quote' / 雪", nil])
check(r.rows[0]['id'] == 9_007_199_254_740_993 && r.rows[0]['amount'] == '1.00000000000000001' && r.raw['future_field']['kept'])
r = c.sql.run('contract:update')
check(r.rows_affected == 2 && r.rows_buffered == 3 && r.rows.length == 1 && r.columns == ['id'])
r = c.sql.run('contract:unknown')
check(r.kind == 'future_statement' && r.rows_affected.nil?)
%w[batch unavailable unauthorized redirect malformed invalid-rows].each do |name|
  caught = false
  begin
    c.sql.run("contract:#{name}")
  rescue OriginChainDB::Error => e
    caught = true
    check(e.result.results[0].rows_affected == 1) if name == 'batch'
    check(e.status == 401 && e.request_id == '84f92822-5837-432e-981a-7b24ad65e16c') if name == 'unauthorized'
    check(e.status == 503 && e.retry_after == '0') if name == 'unavailable'
  end
  check(caught)
end
c.rows.get('demo/items', 'a b?/%')
c.rows.put('demo.items', { id: 'one', nullable: nil })
c.rows.put_batch('demo.items', [{ id: 'one' }, { id: 'two' }])
c.schemas.list
c.schemas.register("[schema]\nname=\"demo.items\"\n")
c.vector.put('demo.items', 'one', [1.0, 0.0], metadata: { tag: 'test' })
check(c.vector.search('demo.items', [1.0, 0.0]).map(&:id) == ['one', 'two'])
c.vector.delete('demo.items', 'one')
c.fts.index('demo.items', 'body', 'one', 'hello world')
check(c.fts.search('demo.items', 'body', 'hello').hits[0].doc_id == 'one')
phrase = c.fts.search('demo.items', 'body', 'phrase', mode: 'phrase')
check(phrase.hits[0].doc_id == 'two' && phrase.hits[0].score == 0)
enriched = c.fts.search('demo.items', 'body', 'highlight', highlight: true, facets: ['tag'])
check(enriched.facets && enriched.hits[0].highlights)
c.graph.query('MATCH (n) RETURN $name', params: { name: 'one' })
c.graph.neighbors('demo.items', 'one', 'related')
c.graph.bfs('demo.items', 'one', 'related', max_depth: 5)
c.close
puts 'Ruby consumer assertions passed'

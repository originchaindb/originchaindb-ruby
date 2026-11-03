# Using the client

Create `db` as shown in the [quickstart](../README.md). These independent examples
assume an existing `demo.items` schema and an appropriate search index.

```ruby
result = db.sql.run('SELECT $1 AS value', params: [7])
row = db.rows.get('demo.items', 'one')
vectors = db.vector.search('demo.items', [1.0, 0.0])
text = db.fts.search('demo.items', 'body', 'hello')
graph = db.graph.query('MATCH (n) RETURN $name', params: { name: 'one' })
```

## Results, errors, and lifetime

`SqlResult#rows` contains hashes with string keys. `rows_affected` is an
Integer or nil. Vector hits expose `id`, `score`, `metadata`, and `raw`.
Full-text results expose `hits`, `facets`, and `raw`.

Rescue `OriginChainDB::Error`; inspect `kind`, `status`, and `request_id`.
`result` contains a partial SQL result for batch errors.

Use `Client.from_env(timeout: 10)`. Timeouts apply to connection, read, and write
inactivity. Each client serializes calls over a persistent connection; use one
client per parallel worker. Close it in an `ensure` block.

See the [shared behavior contract](contract.md) for parameter binding, batch
semantics, defaults, and retry behavior. The [contract consumer](../tests/consumer.rb)
exercises the full common API against a local fixture.

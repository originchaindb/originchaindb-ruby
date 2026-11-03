require_relative 'lib/originchaindb/version'
Gem::Specification.new do |s|
  s.name = 'originchaindb'
  s.version = OriginChainDB::VERSION
  s.summary = 'The official OriginChainDB client for Ruby'
  s.description = 'A handwritten client for SQL, vector, full-text and graph operations.'
  s.authors = ['OriginChainDB']
  s.license = 'MIT'
  s.homepage = 'https://github.com/originchaindb/originchaindb-ruby'
  s.required_ruby_version = '>= 3.2'
  s.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE', 'CHANGELOG.md']
  s.metadata = { 'source_code_uri' => s.homepage, 'bug_tracker_uri' => "#{s.homepage}/issues", 'rubygems_mfa_required' => 'true' }
  # JSON is part of every supported Ruby runtime; no native extension install is needed.
  s.add_dependency 'net-http', '>= 0.4', '< 1'
end

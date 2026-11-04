# frozen_string_literal: true
require 'json'
root = File.expand_path(ARGV[0] || '..', __dir__)
require File.join(root, 'lib/originchaindb')
surface = {}
OriginChainDB.constants(false).sort.each do |name|
  object = OriginChainDB.const_get(name)
  next unless object.is_a?(Class)
  prefix = "OriginChainDB::#{name}"
  surface[prefix] = "class < #{object.superclass}"
  surface[prefix + '.members'] = object.members.join(',') if object.respond_to?(:members)
  methods = object.public_instance_methods(false)
  methods << :initialize if object.private_instance_methods(false).include?(:initialize)
  methods.sort.each do |method_name|
    method = object.instance_method(method_name)
    next unless method.source_location
    surface[prefix + '#' + method_name.to_s] = JSON.generate(method.parameters)
  end
  object.singleton_methods(false).sort.each do |method_name|
    method = object.method(method_name)
    # Built-in Data/Struct constructors vary by Ruby release; their fields are guarded above.
    next unless method.source_location
    surface[prefix + '.' + method_name.to_s] = JSON.generate(method.parameters)
  end
end
puts JSON.generate(surface.sort.to_h)

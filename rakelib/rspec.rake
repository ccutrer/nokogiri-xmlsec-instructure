# frozen_string_literal: true

require "ruby_memcheck"
require "ruby_memcheck/rspec/rake_task"

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new :spec

namespace :spec do
  RubyMemcheck::RSpec::RakeTask.new(valgrind: :compile)
end

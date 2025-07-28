# frozen_string_literal: true

#
# Tasks are all loaded from `rakelib/*.rake`.
# You may want to use `rake -T` to see what's available.
#
require "bundler"
NOKOGIRI_XMLSEC_SPEC = Bundler.load_gemspec("nokogiri-xmlsec-instructure.gemspec")

task default: %i[rubocop compile spec]

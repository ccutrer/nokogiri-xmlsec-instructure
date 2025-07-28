# frozen_string_literal: true

require "nokogiri/xmlsec/version"

# backcompat
module Xmlsec
  VERSION = Nokogiri::Xmlsec::VERSION
end

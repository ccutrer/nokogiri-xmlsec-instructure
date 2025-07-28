# frozen_string_literal: true

# load the C extension
begin
  # native precompiled gems package shared libraries in <gem_dir>/lib/nokogiri/xmlsec/<ruby_version>
  RUBY_VERSION =~ /(\d+\.\d+)/
  require_relative "#{Regexp.last_match(1)}/nokogiri_xmlsec"
rescue LoadError => e
  if e.message.include?("GLIBC")
    warn(<<~TEXT)

      ERROR: It looks like you're trying to use Nokogiri-XMLSec as a precompiled native gem on a system
             with an unsupported version of glibc.

        #{e.message}

        If that's the case, then please install Nokogiri-XMLSec via the `ruby` platform gem:
            gem install nokogiri-xmlsec-instructure --platform=ruby
        or, in your Gemfile:
            gem "nokogiri-xmlsec-instructure", force_ruby_platform: true

        Please visit https://nokogiri.org/tutorials/installing_nokogiri.html for more help.

    TEXT
    raise e
  end

  # use "require" instead of "require_relative" because non-native gems will place C extension files
  # in Gem::BasicSpecification#extension_dir after compilation (during normal installation), which
  # is in $LOAD_PATH but not necessarily relative to this file (see #2300)
  require "nokogiri/xmlsec/nokogiri_xmlsec"
end

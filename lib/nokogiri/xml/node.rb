# frozen_string_literal: true

module Nokogiri
  module XML
    class Node
      def encrypt_with(key:, name: nil, **opts)
        raise ArgumentError("public :key is required for encryption") unless key

        encrypt_with_key(name, key, opts)
      end

      def decrypt_with(opts)
        raise "inadequate options specified for decryption" unless opts[:key]

        parent = self.parent
        previous = self.previous
        key = opts[:key]
        key = key.to_pem if key.respond_to?(:to_pem)
        decrypt_with_key(opts[:name].to_s, key)
        previous ? previous.next : parent.children.first
      end
    end
  end
end

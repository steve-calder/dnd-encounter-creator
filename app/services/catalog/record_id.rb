module Catalog
  # Stable, readable catalog IDs such as "srd-2014--giant-shark".
  module RecordId
    BOOK_KEYS = {
      "Free Basic Rules (2014)" => "srd-2014",
      "Free Basic Rules (2024)" => "srd-2024"
    }.freeze

    class UnknownBook < StandardError; end

    def self.for(book:, name:)
      key = BOOK_KEYS.fetch(book) { raise UnknownBook, "no catalog ID prefix for book #{book.inspect}" }
      "#{key}--#{name.to_s.parameterize}"
    end
  end
end

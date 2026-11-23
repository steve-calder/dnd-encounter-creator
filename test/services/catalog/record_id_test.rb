require "test_helper"

class Catalog::RecordIdTest < ActiveSupport::TestCase
  test "prefixes the book key to the name slug" do
    assert_equal "srd-2014--giant-shark", Catalog::RecordId.for(book: "Free Basic Rules (2014)", name: "Giant Shark")
    assert_equal "srd-2024--draconic-spirit", Catalog::RecordId.for(book: "Free Basic Rules (2024)", name: "Draconic Spirit")
  end

  test "handles punctuation in names" do
    assert_equal "srd-2024--animated-object-small-or-medium",
      Catalog::RecordId.for(book: "Free Basic Rules (2024)", name: "Animated Object (Small or Medium)")
    assert_equal "srd-2014--will-o-wisp", Catalog::RecordId.for(book: "Free Basic Rules (2014)", name: "Will-o'-Wisp")
  end

  test "same-name variants get distinct IDs" do
    assert_not_equal Catalog::RecordId.for(book: "Free Basic Rules (2014)", name: "Ape"),
      Catalog::RecordId.for(book: "Free Basic Rules (2024)", name: "Ape")
  end

  test "rejects books outside the catalog" do
    assert_raises(Catalog::RecordId::UnknownBook) { Catalog::RecordId.for(book: "Tome of Beasts 2", name: "A-mi-kuk") }
  end
end

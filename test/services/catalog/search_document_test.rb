require "test_helper"

class Catalog::SearchDocumentTest < ActiveSupport::TestCase
  def document_for(name, book = "Free Basic Rules (2014)")
    Catalog::SearchDocument.call(Catalog::Normalizer.call(raw_monster(name, book)))
  end

  test "Giant Shark document" do
    document = document_for("Giant Shark")

    assert_equal <<~TEXT.chomp, document
      Giant Shark. Huge beast, Unaligned.
      Movement: Swim 50 ft.
      Senses: Blindsight 60 Ft.
      Traits: Blood Frenzy: The shark has advantage on melee attack rolls against any creature that doesn't have all its hit points. Water Breathing: The shark can breathe only underwater.
      Actions: Bite.
      A giant shark is 30 feet long and normally found in deep oceans. Utterly fearless, it preys on anything that crosses its path, including whales and ships.
    TEXT
  end

  test "non-attack actions keep a short description" do
    document = document_for("Knight")

    assert_match "Multiattack: The knight makes two melee attacks.", document
    assert_match "Greatsword.", document
    assert_no_match(/Greatsword:/, document)
  end

  test "deterministic" do
    assert_equal document_for("Adult Black Dragon"), document_for("Adult Black Dragon")
  end

  test "Roll20 macros and markup are removed" do
    document = document_for("Draconic Spirit", "Free Basic Rules (2024)")

    assert_no_match(/@\{|\[\[|\*/, document)
    assert_match "Breath Weapon:", document
  end

  test "long records stay within 2,000 characters and descriptions are cut" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark"))
    attrs[:traits] = 30.times.map { |i| { "name" => "Trait #{i}", "desc" => "word " * 100 } }
    attrs[:lore] = "lore " * 1_000

    document = Catalog::SearchDocument.call(attrs)

    assert_operator document.length, :<=, 2_000
    assert_match(/Trait 0: (word ){20,}word\.\.\./, document)
  end

  test "lore is cut before structured fields" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark")).merge(lore: "lore " * 1_000)
    document = Catalog::SearchDocument.call(attrs)

    assert_operator document.length, :<=, 2_000
    assert_match "Actions: Bite.", document
    assert document.end_with?("...")
  end
end

require "test_helper"

class Catalog::NormalizerTest < ActiveSupport::TestCase
  test "fixture covers every case the catalog tests rely on" do
    assert_equal srd_fixture["source"]["record_count"], srd_fixture["monsters"].size
    [
      [ "Giant Shark" ], [ "Ape" ], [ "Ape", "Free Basic Rules (2024)" ], [ "Frog" ],
      [ "Draconic Spirit", "Free Basic Rules (2024)" ], [ "Acolyte" ], [ "Knight" ], [ "Adult Black Dragon" ]
    ].each { |name, book| assert raw_monster(name, *book) }
  end

  test "normalizes the Giant Shark stat block" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark"))

    assert_equal "Giant Shark", attrs[:name]
    assert_equal "Free Basic Rules (2014)", attrs[:book]
    assert_equal "Wizards of the Coast", attrs[:publisher]
    assert_equal "Huge", attrs[:size]
    assert_equal "beast", attrs[:creature_type]
    assert_equal "Unaligned", attrs[:alignment]
    assert_equal 5.0, attrs[:challenge_rating]
    assert_equal 13, attrs[:armor_class]
    assert_equal "13 (Natural Armor)", attrs[:armor_class_display]
    assert_equal 126, attrs[:hit_points]
    assert_equal "126 (11d12+55)", attrs[:hit_points_display]
    assert_equal "Swim 50 ft.", attrs[:speed]
    assert_equal({ "str" => 23, "dex" => 11, "con" => 21, "int" => 1, "wis" => 10, "cha" => 5 }, attrs[:abilities])
    assert_equal [ "Blood Frenzy", "Water Breathing" ], attrs[:traits].map { |t| t["name"] }
  end

  test "fractional CR is normalized to a number" do
    attrs = Catalog::Normalizer.call(raw_monster("Acolyte"))

    assert_equal 0.25, attrs[:challenge_rating]
    assert_equal "1/4", attrs[:challenge_rating_display]
  end

  test "non-numeric CR is unresolved" do
    assert_nil Catalog::Normalizer.call(raw_monster("Draconic Spirit", "Free Basic Rules (2024)"))[:challenge_rating]
  end

  test "XP with a thousands separator becomes an integer" do
    assert_equal 1800, Catalog::Normalizer.call(raw_monster("Giant Shark"))[:xp]
    assert_equal 11500, Catalog::Normalizer.call(raw_monster("Adult Black Dragon"))[:xp]
  end

  test "structured attack actions are parsed" do
    bite = Catalog::Normalizer.call(raw_monster("Giant Shark"))[:actions].first

    assert_equal "Bite", bite["name"]
    assert_equal "9", bite["hit_bonus"]
    assert_equal "5 ft.", bite["reach"]
    assert_equal "Melee", bite["attack_range"]
    assert_equal "3d10 + 6", bite["damage"]
    assert_equal "piercing", bite["damage_type"]
  end

  test "reactions, legendary actions, and spells are parsed" do
    assert_equal [ "Parry" ], Catalog::Normalizer.call(raw_monster("Knight"))[:reactions].map { |r| r["name"] }
    assert_includes Catalog::Normalizer.call(raw_monster("Adult Black Dragon"))[:legendary_actions].map { |a| a["name"] }, "Tail Attack"
    assert_equal [ "light", "sacred flame", "thaumaturgy" ], Catalog::Normalizer.call(raw_monster("Acolyte"))[:spells]["cantrips"]
  end

  test "missing sections become empty lists" do
    attrs = Catalog::Normalizer.call(raw_monster("Frog"))

    assert_equal [], attrs[:actions]
    assert_equal [], attrs[:legendary_actions]
  end

  test "source XP is recorded with source provenance" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark"))

    assert_equal "source", attrs[:xp_source]
  end

  test "missing XP is derived from CR with provenance" do
    raw = raw_monster("Giant Shark").deep_dup
    raw["properties"].delete("data-XP")
    attrs = Catalog::Normalizer.call(raw)

    assert_equal 1800, attrs[:xp]
    assert_equal "derived_from_cr", attrs[:xp_source]
  end

  test "missing XP with no unambiguous CR stays unresolved" do
    raw = raw_monster("Frog").deep_dup
    raw["properties"].delete("data-XP")
    attrs = Catalog::Normalizer.call(raw)

    assert_nil attrs[:xp]
    assert_nil attrs[:xp_source]
  end

  test "keeps the original record verbatim" do
    raw = raw_monster("Giant Shark")

    assert_equal raw, Catalog::Normalizer.call(raw)[:source]
  end

  test "lore drops the Roll20 lead-in and the repeated stat block" do
    assert_equal "A giant shark is 30 feet long and normally found in deep oceans. Utterly fearless, it preys on anything that crosses its path, including whales and ships.",
      Catalog::Normalizer.call(raw_monster("Giant Shark"))[:lore]
    assert_nil Catalog::Normalizer.call(raw_monster("Adult Black Dragon"))[:lore]
  end

  test "content hash is stable and changes with the source" do
    raw = raw_monster("Giant Shark")
    changed = raw.deep_dup.tap { |r| r["properties"]["HP"] = "127 (11d12+56)" }

    assert_equal Catalog::Normalizer.call(raw)[:content_hash], Catalog::Normalizer.call(raw.deep_dup)[:content_hash]
    assert_not_equal Catalog::Normalizer.call(raw)[:content_hash], Catalog::Normalizer.call(changed)[:content_hash]
  end
end

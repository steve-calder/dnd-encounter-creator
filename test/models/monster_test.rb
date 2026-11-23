require "test_helper"

class MonsterTest < ActiveSupport::TestCase
  test "saves and reloads with a string ID and nested stat-block data" do
    Monster.create!(
      _id: "srd-2014--giant-shark",
      name: "Giant Shark",
      book: "Free Basic Rules (2014)",
      challenge_rating: 5.0,
      xp: 1800,
      abilities: { "str" => 23, "dex" => 11, "con" => 21, "int" => 1, "wis" => 10, "cha" => 5 },
      actions: [ { "name" => "Bite", "hit_bonus" => 9, "damage" => "3d10 + 6" } ],
      source: { "name" => "Giant Shark", "properties" => { "data-XP" => "1,800" } }
    )

    monster = Monster.find("srd-2014--giant-shark")

    assert_equal "Giant Shark", monster.name
    assert_equal 23, monster.abilities["str"]
    assert_equal "Bite", monster.actions.first["name"]
    assert_equal 9, monster.actions.first["hit_bonus"]
    assert_equal "1,800", monster.source.dig("properties", "data-XP")
    assert_equal false, monster.eligible
    assert_equal [], monster.ineligibility_reasons
  end

  test "ability modifier rounds down" do
    assert_equal 6, Monster.ability_modifier(23)
    assert_equal 0, Monster.ability_modifier(11)
    assert_equal(-3, Monster.ability_modifier(5))
    assert_equal(-5, Monster.ability_modifier(1))
  end
end

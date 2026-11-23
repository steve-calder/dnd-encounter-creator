require "test_helper"

class MonstersControllerTest < ActionDispatch::IntegrationTest
  ATTRIBUTION = "System Reference Document 5.1 and 5.2 by Wizards of the Coast LLC"

  setup { Catalog::Importer.new(dataset: Catalog::Dataset.load(srd_fixture_path)).call }

  test "root shows the catalog" do
    get root_path

    assert_response :success
    assert_select "h1", "Monster catalog"
  end

  test "listing shows same-name variants separately, each linking to its stat block" do
    get monsters_path

    assert_select "#monster_srd-2014--ape td", text: "Free Basic Rules (2014)"
    assert_select "#monster_srd-2024--ape td", text: "Free Basic Rules (2024)"
    assert_select "a[href=?]", monster_path("srd-2014--ape"), text: "Ape"
    assert_select "a[href=?]", monster_path("srd-2024--ape"), text: "Ape"
  end

  test "listing marks ineligible records" do
    get monsters_path

    assert_select "#monster_srd-2024--draconic-spirit .badge-no", text: "Not eligible"
    assert_select "#monster_srd-2014--giant-shark .badge-ok", text: "Eligible"
  end

  test "listing shows CR and XP" do
    get monsters_path

    assert_select "#monster_srd-2014--giant-shark td.num", text: "5"
    assert_select "#monster_srd-2014--giant-shark td.num", text: "1,800"
  end

  test "name filter is a case-insensitive substring" do
    get monsters_path, params: { q: "SHARK" }

    assert_select "tbody tr", 2
    assert_select "tbody a", text: "Giant Shark"
    assert_select "tbody a", text: "Reef Shark"
  end

  test "name filter treats special characters literally" do
    get monsters_path, params: { q: ".*" }

    assert_response :success
    assert_select "tbody tr", 0
    assert_select "p.empty"
  end

  test "Giant Shark stat block" do
    get monster_path("srd-2014--giant-shark")

    assert_response :success
    assert_select ".stat-block h1", "Giant Shark"
    assert_select ".stat-subtitle", "Huge beast, Unaligned"
    assert_select ".stat-lines", text: /Armor Class\s+13 \(Natural Armor\)/
    assert_select ".stat-lines", text: /Hit Points\s+126 \(11d12\+55\)/
    assert_select ".stat-lines", text: /Speed\s+Swim 50 ft\./
    assert_select "table.abilities td", text: "23 (+6)"
    assert_select "table.abilities td", text: "5 (−3)"
    assert_select ".stat-lines", text: /Skills\s+Perception \+3/
    assert_select ".stat-lines", text: /Senses\s+Blindsight 60 Ft\./
    assert_select ".stat-lines", text: /Challenge\s+5 \(1,800 XP\)/
    assert_select ".stat-entry", text: /Blood Frenzy\./
    assert_select ".stat-entry", text: /Water Breathing\./
    assert_select ".stat-entry", text: /Bite\.\s+Melee Weapon Attack: \+9 to hit, reach 5 ft\., one target\. Hit: 3d10 \+ 6 piercing damage\./
  end

  test "stat block omits sections with no entries" do
    get monster_path("srd-2014--giant-shark")

    assert_select ".stat-block h2", text: "Actions"
    assert_select ".stat-block h2", text: "Reactions", count: 0
    assert_select ".stat-block h2", text: "Legendary Actions", count: 0
    assert_select ".stat-block h2", text: "Bonus Actions", count: 0
    assert_select ".stat-block h2", text: "Spells", count: 0
  end

  test "stat block shows reactions, legendary actions, and spells when present" do
    get monster_path("srd-2014--knight")
    assert_select ".stat-block h2", text: "Reactions"
    assert_select ".stat-entry", text: /Heavy Crossbow\.\s+Ranged Weapon Attack: \+2 to hit, range 100\/400 ft\., one target\./

    get monster_path("srd-2014--adult-black-dragon")
    assert_select ".stat-block h2", text: "Legendary Actions"
    assert_select ".stat-block .stat-lines", text: /Saving Throws\s+Dex \+7/

    get monster_path("srd-2014--acolyte")
    assert_select ".stat-block h2", text: "Spells"
    assert_select ".stat-block p", text: /Cantrips \(at will\):\s+light, sacred flame, thaumaturgy/
  end

  test "stat block shows source and XP provenance" do
    get monster_path("srd-2014--giant-shark")

    assert_select ".catalog-meta dd", text: "Free Basic Rules (2014) (Wizards of the Coast)"
    assert_select ".catalog-meta dd", text: "1,800 — from the source data"
    assert_select ".catalog-meta .badge-ok", text: "Eligible"
  end

  test "ineligible stat block explains why" do
    get monster_path("srd-2024--draconic-spirit")

    assert_response :success
    assert_select ".notice-ineligible", text: /Not eligible/
    assert_select ".notice-ineligible li", text: "Challenge rating is missing or not a number"
    assert_select ".notice-ineligible li", text: "XP is 0"
  end

  test "unknown ID returns 404" do
    get monster_path("srd-2014--no-such-monster")

    assert_response :not_found
  end

  test "source text is escaped" do
    shark = Monster.find("srd-2014--giant-shark")
    shark.update!(traits: [ { "name" => "Evil <b>Trait</b>", "desc" => "<script>alert('x')</script>" } ])

    get monster_path(shark)

    assert_includes response.body, "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"
    assert_not_includes response.body, "<script>alert"
    assert_includes response.body, "Evil &lt;b&gt;Trait&lt;/b&gt;"
  end

  test "SRD attribution appears on catalog and stat block pages" do
    get monsters_path
    assert_select ".attribution", text: /#{ATTRIBUTION}/
    assert_select ".attribution a[href='https://creativecommons.org/licenses/by/4.0/legalcode']"

    get monster_path("srd-2014--giant-shark")
    assert_select ".attribution", text: /#{ATTRIBUTION}/
  end
end

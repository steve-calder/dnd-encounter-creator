require "test_helper"

class Catalog::EligibilityTest < ActiveSupport::TestCase
  def reasons_for(name, book = "Free Basic Rules (2014)")
    Catalog::Eligibility.reasons(Catalog::Normalizer.call(raw_monster(name, book)))
  end

  test "spell summon with CR None and XP 0 is excluded" do
    reasons = reasons_for("Draconic Spirit", "Free Basic Rules (2024)")

    assert_includes reasons, "cr_unresolved"
    assert_includes reasons, "xp_zero"
  end

  test "complete record is eligible" do
    assert_empty reasons_for("Giant Shark")
  end

  test "a record without actions is still eligible" do
    assert_empty reasons_for("Frog")
  end

  test "missing stat block fields make a record incomplete" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark"))

    assert_equal [ "incomplete_stat_block" ], Catalog::Eligibility.reasons(attrs.merge(hit_points: nil))
    assert_equal [ "incomplete_stat_block" ], Catalog::Eligibility.reasons(attrs.merge(abilities: attrs[:abilities].merge("cha" => nil)))
  end

  test "unresolved XP is reported" do
    attrs = Catalog::Normalizer.call(raw_monster("Giant Shark"))

    assert_equal [ "xp_unresolved" ], Catalog::Eligibility.reasons(attrs.merge(xp: nil))
  end
end

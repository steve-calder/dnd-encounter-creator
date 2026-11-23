require "test_helper"

class Catalog::CrXpTest < ActiveSupport::TestCase
  test "maps representative challenge ratings to XP" do
    assert_equal 25, Catalog::CrXp.xp_for(0.125)
    assert_equal 50, Catalog::CrXp.xp_for(0.25)
    assert_equal 100, Catalog::CrXp.xp_for(Rational(1, 2))
    assert_equal 1_800, Catalog::CrXp.xp_for(5)
    assert_equal 1_800, Catalog::CrXp.xp_for(5.0)
    assert_equal 155_000, Catalog::CrXp.xp_for(30)
  end

  test "does not derive XP for CR 0, which is worth 0 or 10" do
    assert_nil Catalog::CrXp.xp_for(0)
  end

  test "returns nil for unknown or missing CR" do
    assert_nil Catalog::CrXp.xp_for(nil)
    assert_nil Catalog::CrXp.xp_for(31)
    assert_nil Catalog::CrXp.xp_for(1.8)
  end
end

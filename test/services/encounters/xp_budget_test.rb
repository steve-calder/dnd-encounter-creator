require "test_helper"

class Encounters::XpBudgetTest < ActiveSupport::TestCase
  def budget(levels, difficulty)
    Encounters::XpBudget.for(levels: levels, difficulty: difficulty)
  end

  test "level 5 per-character values" do
    assert_equal 500, budget([ 5 ], :low)
    assert_equal 750, budget([ 5 ], :moderate)
    assert_equal 1_100, budget([ 5 ], :high)
  end

  test "table bounds" do
    assert_equal 100, budget([ 1 ], :high)
    assert_equal 22_000, budget([ 20 ], :high)
  end

  test "table covers levels 1 to 20 for every difficulty, rising with level" do
    assert_equal (1..20).to_a, Encounters::XpBudget::TABLE.keys
    Encounters::XpBudget::DIFFICULTIES.each do |difficulty|
      values = Encounters::XpBudget::TABLE.values.map { |row| row.fetch(difficulty) }
      assert_equal values.sort, values, "#{difficulty} column should increase with level"
    end
  end

  test "boat example: three level-5 characters" do
    party = [ 5, 5, 5 ]

    assert_equal 1_500, budget(party, "Low")
    assert_equal 2_250, budget(party, "Moderate")
    assert_equal 3_300, budget(party, "High")
  end

  test "mixed-level party sums per-character budgets" do
    assert_equal 975, budget([ 3, 5 ], :moderate)
  end

  test "empty party is rejected" do
    error = assert_raises(Encounters::XpBudget::InvalidParty) { budget([], :low) }
    assert_match "at least one character", error.message
  end

  test "levels outside 1 to 20 are rejected and named" do
    error = assert_raises(Encounters::XpBudget::InvalidParty) { budget([ 5, 21 ], :low) }
    assert_match "21", error.message

    error = assert_raises(Encounters::XpBudget::InvalidParty) { budget([ 0 ], :low) }
    assert_match "0", error.message
  end

  test "non-integer levels are rejected and named" do
    error = assert_raises(Encounters::XpBudget::InvalidParty) { budget([ 4.5 ], :low) }
    assert_match "4.5", error.message

    error = assert_raises(Encounters::XpBudget::InvalidParty) { budget([ "five" ], :low) }
    assert_match '"five"', error.message

    assert_raises(Encounters::XpBudget::InvalidParty) { budget([ "5" ], :low) }
    assert_raises(Encounters::XpBudget::InvalidParty) { budget(5, :low) }
  end

  test "difficulty is case-insensitive" do
    assert_equal 750, budget([ 5 ], "moderate")
    assert_equal 750, budget([ 5 ], "MODERATE")
    assert_equal 750, budget([ 5 ], :Moderate)
  end

  test "unknown difficulty is rejected with the accepted list" do
    error = assert_raises(Encounters::XpBudget::InvalidDifficulty) { budget([ 5 ], "Deadly") }
    assert_match '"Deadly"', error.message
    assert_match "low, moderate, high", error.message

    assert_raises(Encounters::XpBudget::InvalidDifficulty) { budget([ 5 ], nil) }
  end

  test "errors are ArgumentErrors" do
    assert_operator Encounters::XpBudget::InvalidParty, :<, ArgumentError
    assert_operator Encounters::XpBudget::InvalidDifficulty, :<, ArgumentError
  end
end

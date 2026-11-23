require "test_helper"

# The design doc's acceptance example: three level-5 PCs on a boat, sea creatures,
# Moderate difficulty. The budget feeds lineup evaluation as the ceiling.
class Encounters::BoatAcceptanceTest < ActiveSupport::TestCase
  setup do
    Catalog::Importer.new(dataset: Catalog::Dataset.load(srd_fixture_path)).call
    @budget = Encounters::XpBudget.for(levels: [ 5, 5, 5 ], difficulty: "Moderate")
  end

  test "Moderate budget for three level-5 PCs is 2,250" do
    assert_equal 2_250, @budget
  end

  test "a sea-creature lineup within the budget is valid" do
    result = Encounters::LineupEvaluation.call(
      entries: [ { "id" => "srd-2014--giant-shark", "quantity" => 1 }, { "id" => "srd-2014--reef-shark", "quantity" => 4 } ],
      budget: @budget
    )

    assert result.valid?, result.problems.map(&:message).join("; ")
    assert_equal 2_200, result.total_xp
    assert_equal 50, result.remaining_xp
  end

  test "two Giant Sharks exceed the budget" do
    result = Encounters::LineupEvaluation.call(entries: [ { "id" => "srd-2014--giant-shark", "quantity" => 2 } ], budget: @budget)

    assert_not result.valid?
    assert_equal 3_600, result.total_xp
    assert_equal [ "over_budget" ], result.problems.map(&:code)
  end
end

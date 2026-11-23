require "test_helper"

class Encounters::LineupEvaluationTest < ActiveSupport::TestCase
  SHARK = "srd-2014--giant-shark"
  ACOLYTE = "srd-2014--acolyte"
  KNIGHT = "srd-2014--knight"

  setup { Catalog::Importer.new(dataset: Catalog::Dataset.load(srd_fixture_path)).call }

  def evaluate(entries, budget: 2_250)
    Encounters::LineupEvaluation.call(entries: entries, budget: budget)
  end

  def codes(result) = result.problems.map(&:code)

  test "valid lineup reports totals and no problems" do
    result = evaluate([ { "id" => SHARK, "quantity" => 1 }, { "id" => ACOLYTE, "quantity" => 9 } ])

    assert result.valid?
    assert_equal 2_250, result.total_xp
    assert_equal 2_250, result.budget
    assert_equal 0, result.remaining_xp
    assert_empty result.problems
    assert_equal [ [ SHARK, 1_800 ], [ ACOLYTE, 450 ] ], result.entries.map { |e| [ e.id, e.subtotal ] }
  end

  test "symbol keys are accepted" do
    assert evaluate([ { id: SHARK, quantity: 1 } ]).valid?
  end

  test "totals are still reported when invalid, counting only resolvable entries" do
    result = evaluate([ { "id" => SHARK, "quantity" => 1 }, { "id" => "srd-2014--tarrasque-jr", "quantity" => 3 } ])

    assert_not result.valid?
    assert_equal 1_800, result.total_xp
    assert_equal 450, result.remaining_xp
  end

  test "over budget states the overage" do
    result = evaluate([ { "id" => SHARK, "quantity" => 1 }, { "id" => KNIGHT, "quantity" => 1 } ])

    assert_not result.valid?
    assert_equal [ "over_budget" ], codes(result)
    assert_equal(-250, result.remaining_xp)
    assert_equal "Total 2,500 XP is 250 XP over the 2,250 XP budget.", result.problems.first.message
  end

  test "exactly on budget is valid" do
    assert evaluate([ { "id" => KNIGHT, "quantity" => 2 } ], budget: 1_400).valid?
  end

  test "unknown ID is reported by name" do
    result = evaluate([ { "id" => "srd-2014--tarrasque-jr", "quantity" => 1 } ])

    problem = result.problems.sole
    assert_equal "unknown_id", problem.code
    assert_equal "srd-2014--tarrasque-jr", problem.id
    assert_match "srd-2014--tarrasque-jr", problem.message
  end

  test "each invalid quantity is reported with its value" do
    result = evaluate([
      { "id" => SHARK, "quantity" => 0 },
      { "id" => ACOLYTE, "quantity" => -2 },
      { "id" => KNIGHT, "quantity" => 1.5 },
      { "id" => "srd-2014--frog", "quantity" => "3" },
      { "id" => "srd-2014--ape" }
    ])

    quantity_problems = result.problems.select { |p| p.code == "invalid_quantity" }
    assert_equal [ SHARK, ACOLYTE, KNIGHT, "srd-2014--frog", "srd-2014--ape" ], quantity_problems.map(&:id)
    assert_match "got 0", quantity_problems[0].message
    assert_match "got -2", quantity_problems[1].message
    assert_match "got 1.5", quantity_problems[2].message
    assert_match 'got "3"', quantity_problems[3].message
    assert_match "missing", quantity_problems[4].message
    assert_equal 0, result.total_xp
  end

  test "ineligible record is reported with its reasons" do
    result = evaluate([ { "id" => "srd-2024--draconic-spirit", "quantity" => 1 } ])

    problem = result.problems.sole
    assert_equal "ineligible", problem.code
    assert_equal "srd-2024--draconic-spirit", problem.id
    assert_match "cr_unresolved", problem.message
    assert_match "xp_zero", problem.message
  end

  test "repeated ID is a duplicate entry and still counts toward the total" do
    result = evaluate([ { "id" => SHARK, "quantity" => 1 }, { "id" => SHARK, "quantity" => 1 } ], budget: 5_000)

    problem = result.problems.sole
    assert_equal "duplicate_entry", problem.code
    assert_equal SHARK, problem.id
    assert_equal 3_600, result.total_xp
  end

  test "two variants of one creature are rejected" do
    result = evaluate([ { "id" => "srd-2014--ape", "quantity" => 1 }, { "id" => "srd-2024--ape", "quantity" => 1 } ])

    problem = result.problems.sole
    assert_equal "multiple_variants", problem.code
    assert_match "Ape", problem.message
    assert_match "srd-2014--ape", problem.message
    assert_match "srd-2024--ape", problem.message
  end

  test "empty lineup is invalid with a total of 0" do
    result = evaluate([])

    assert_equal [ "empty_lineup" ], codes(result)
    assert_equal 0, result.total_xp
  end

  test "malformed entries are reported, not raised" do
    result = evaluate([ "srd-2014--giant-shark", { "quantity" => 1 }, { "id" => 42, "quantity" => 1 } ])

    assert_equal [ "invalid_entry" ] * 3, codes(result)
    assert_equal [ "invalid_entry" ], codes(evaluate("not a list"))
  end

  test "several problems are reported together, each with code, id, and message" do
    result = evaluate([
      { "id" => SHARK, "quantity" => 2 },
      { "id" => "srd-2014--tarrasque-jr", "quantity" => 1 },
      { "id" => KNIGHT, "quantity" => 0 }
    ])

    assert_equal [ "unknown_id", "invalid_quantity", "over_budget" ], codes(result)
    assert_equal [ "srd-2014--tarrasque-jr", KNIGHT, nil ], result.problems.map(&:id)
    assert result.problems.all? { |p| p.message.present? }
  end

  test "to_h is JSON-ready" do
    hash = evaluate([ { "id" => SHARK, "quantity" => 2 } ]).to_h

    assert_equal false, hash[:valid]
    assert_equal 3_600, hash[:total_xp]
    assert_equal(-1_350, hash[:remaining_xp])
    assert_equal({ id: SHARK, name: "Giant Shark", book: "Free Basic Rules (2014)", xp: 1_800, quantity: 2, subtotal: 3_600 }, hash[:entries].sole)
    assert_equal "over_budget", hash[:problems].sole[:code]
    assert_nothing_raised { JSON.generate(hash) }
  end

  test "budget must be a positive integer" do
    assert_raises(ArgumentError) { evaluate([], budget: 0) }
    assert_raises(ArgumentError) { evaluate([], budget: "2250") }
    assert_raises(ArgumentError) { evaluate([], budget: nil) }
  end
end

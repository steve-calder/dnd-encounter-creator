module Encounters
  # Validates a proposed monster lineup against the catalog and an XP budget.
  # Input is treated as untrusted (for example, JSON from an LLM tool call):
  # every problem is collected and reported, nothing is coerced.
  #
  #   result = Encounters::LineupEvaluation.call(
  #     entries: [ { "id" => "srd-2014--giant-shark", "quantity" => 1 } ],
  #     budget: 2250
  #   )
  #   result.valid? # => true
  module LineupEvaluation
    Problem = Data.define(:code, :id, :message)

    Entry = Data.define(:id, :name, :book, :xp, :quantity) do
      def subtotal = xp * quantity
      def to_h = super.merge(subtotal: subtotal)
    end

    Result = Data.define(:total_xp, :budget, :entries, :problems) do
      def valid? = problems.empty?
      def remaining_xp = budget - total_xp

      def to_h
        {
          valid: valid?,
          total_xp: total_xp,
          budget: budget,
          remaining_xp: remaining_xp,
          entries: entries.map(&:to_h),
          problems: problems.map(&:to_h)
        }
      end
    end

    RECORD_FIELDS = %i[ name book xp eligible ineligibility_reasons ].freeze

    module_function

    def call(entries:, budget:)
      raise ArgumentError, "budget must be a positive integer, got #{budget.inspect}" unless budget.is_a?(Integer) && budget.positive?

      unless entries.is_a?(Array)
        return Result.new(total_xp: 0, budget: budget, entries: [],
          problems: [ Problem.new(code: "invalid_entry", id: nil, message: "The lineup must be a list of entries, each with an id and a quantity.") ])
      end

      problems = []
      problems << Problem.new(code: "empty_lineup", id: nil, message: "The lineup has no monsters.") if entries.empty?

      parsed = entries.map { |entry| parse(entry) }
      ids = parsed.filter_map { |entry| entry[:id] }
      records = Monster.in(_id: ids.uniq).only(*RECORD_FIELDS).index_by(&:id)

      resolved = []
      reported_ineligible = Set.new
      parsed.each_with_index do |entry, index|
        problems.concat(entry_problems(entry, index, records, reported_ineligible))
        record = records[entry[:id]]
        resolved << Entry.new(id: record.id, name: record.name, book: record.book, xp: record.xp.to_i, quantity: entry[:quantity]) if record && valid_quantity?(entry[:quantity])
      end

      problems.concat(duplicate_problems(ids))
      problems.concat(variant_problems(resolved))

      total = resolved.sum(&:subtotal)
      problems << over_budget(total, budget) if total > budget

      Result.new(total_xp: total, budget: budget, entries: resolved, problems: problems)
    end

    def parse(entry)
      return { invalid: true } unless entry.is_a?(Hash)

      id = entry.key?("id") ? entry["id"] : entry[:id]
      quantity_given = entry.key?("quantity") || entry.key?(:quantity)
      quantity = entry.key?("quantity") ? entry["quantity"] : entry[:quantity]
      { id: id.is_a?(String) && id.present? ? id : nil, raw_id: id, quantity: quantity, quantity_given: quantity_given }
    end

    def entry_problems(entry, index, records, reported_ineligible)
      position = "Entry #{index + 1}"
      return [ Problem.new(code: "invalid_entry", id: nil, message: "#{position} must be an object with an id and a quantity.") ] if entry[:invalid]
      return [ Problem.new(code: "invalid_entry", id: nil, message: "#{position} needs a catalog id string, got #{entry[:raw_id].inspect}.") ] unless entry[:id]

      id = entry[:id]
      record = records[id]
      problems = []
      problems << Problem.new(code: "unknown_id", id: id, message: "#{id} is not in the monster catalog.") unless record

      unless valid_quantity?(entry[:quantity])
        given = entry[:quantity_given] ? "got #{entry[:quantity].inspect}" : "but it is missing"
        problems << Problem.new(code: "invalid_quantity", id: id, message: "Quantity for #{id} must be a positive integer, #{given}.")
      end

      if record && !record.eligible && reported_ineligible.add?(id)
        reasons = Array(record.ineligibility_reasons).join(", ")
        problems << Problem.new(code: "ineligible", id: id, message: "#{record.name} (#{id}) is not eligible for generation: #{reasons}.")
      end

      problems
    end

    def valid_quantity?(quantity)
      quantity.is_a?(Integer) && quantity >= 1
    end

    def duplicate_problems(ids)
      ids.tally.select { |_, count| count > 1 }.map do |id, count|
        Problem.new(code: "duplicate_entry", id: id, message: "#{id} is listed #{count} times; list each monster once with its total quantity.")
      end
    end

    def variant_problems(resolved)
      resolved.uniq(&:id).group_by { |entry| entry.name.to_s.downcase }.values.select { |group| group.size > 1 }.map do |group|
        ids = group.map(&:id).sort
        Problem.new(code: "multiple_variants", id: nil,
          message: "Use only one version of #{group.first.name}; the lineup includes #{ids.join(" and ")}.")
      end
    end

    def over_budget(total, budget)
      Problem.new(code: "over_budget", id: nil,
        message: "Total #{delimited(total)} XP is #{delimited(total - budget)} XP over the #{delimited(budget)} XP budget.")
    end

    def delimited(number)
      ActiveSupport::NumberHelper.number_to_delimited(number)
    end
  end
end

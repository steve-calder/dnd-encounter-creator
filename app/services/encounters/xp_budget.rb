module Encounters
  # 2024 5e encounter XP budget: the sum of each character's per-character budget
  # for the chosen difficulty. The budget is a ceiling for the encounter's total XP.
  module XpBudget
    DIFFICULTIES = %i[ low moderate high ].freeze

    # "XP Budget per Character", D&D 2024 Basic Rules, DM's Toolbox, Step 2:
    # Determine Your XP Budget. The rules multiply by party size for a single
    # level; summing per character for mixed-level parties is a v1 assumption.
    TABLE = {
      1 => { low: 50, moderate: 75, high: 100 },
      2 => { low: 100, moderate: 150, high: 200 },
      3 => { low: 150, moderate: 225, high: 400 },
      4 => { low: 250, moderate: 375, high: 500 },
      5 => { low: 500, moderate: 750, high: 1_100 },
      6 => { low: 600, moderate: 1_000, high: 1_400 },
      7 => { low: 750, moderate: 1_300, high: 1_700 },
      8 => { low: 1_000, moderate: 1_700, high: 2_100 },
      9 => { low: 1_300, moderate: 2_000, high: 2_600 },
      10 => { low: 1_600, moderate: 2_300, high: 3_100 },
      11 => { low: 1_900, moderate: 2_900, high: 4_100 },
      12 => { low: 2_200, moderate: 3_700, high: 4_700 },
      13 => { low: 2_600, moderate: 4_200, high: 5_400 },
      14 => { low: 2_900, moderate: 4_900, high: 6_200 },
      15 => { low: 3_300, moderate: 5_400, high: 7_800 },
      16 => { low: 3_800, moderate: 6_100, high: 9_800 },
      17 => { low: 4_500, moderate: 7_200, high: 11_700 },
      18 => { low: 5_000, moderate: 8_700, high: 14_200 },
      19 => { low: 5_500, moderate: 10_700, high: 17_200 },
      20 => { low: 6_400, moderate: 13_200, high: 22_000 }
    }.freeze

    class InvalidParty < ArgumentError; end
    class InvalidDifficulty < ArgumentError; end

    module_function

    # levels: an Array of Integer character levels (1-20), one per character.
    # difficulty: "low", "moderate", or "high" (String or Symbol, any case).
    def for(levels:, difficulty:)
      key = difficulty_key(difficulty)
      validate_levels!(levels)
      levels.sum { |level| TABLE.fetch(level).fetch(key) }
    end

    def difficulty_key(difficulty)
      key = difficulty.to_s.strip.downcase.to_sym if difficulty.is_a?(String) || difficulty.is_a?(Symbol)
      return key if DIFFICULTIES.include?(key)

      raise InvalidDifficulty, "unknown difficulty #{difficulty.inspect}; expected one of #{DIFFICULTIES.map(&:to_s).join(", ")}"
    end

    def validate_levels!(levels)
      raise InvalidParty, "party must be a list of character levels, got #{levels.inspect}" unless levels.is_a?(Array)
      raise InvalidParty, "party needs at least one character" if levels.empty?

      invalid = levels.reject { |level| level.is_a?(Integer) && TABLE.key?(level) }
      return if invalid.empty?

      raise InvalidParty, "invalid character level#{"s" if invalid.size > 1} #{invalid.map(&:inspect).join(", ")}; levels must be integers from 1 to 20"
    end
  end
end

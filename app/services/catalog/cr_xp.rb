module Catalog
  # Standard 5e challenge rating to XP table (identical in the 2014 and 2024 rules).
  #
  # CR 0 is deliberately absent: it is worth "0 or 10" XP, so it does not map to
  # exactly one value and XP is never derived from it.
  module CrXp
    TABLE = {
      Rational(1, 8) => 25, Rational(1, 4) => 50, Rational(1, 2) => 100,
      1 => 200, 2 => 450, 3 => 700, 4 => 1_100, 5 => 1_800,
      6 => 2_300, 7 => 2_900, 8 => 3_900, 9 => 5_000, 10 => 5_900,
      11 => 7_200, 12 => 8_400, 13 => 10_000, 14 => 11_500, 15 => 13_000,
      16 => 15_000, 17 => 18_000, 18 => 20_000, 19 => 22_000, 20 => 25_000,
      21 => 33_000, 22 => 41_000, 23 => 50_000, 24 => 62_000, 25 => 75_000,
      26 => 90_000, 27 => 105_000, 28 => 120_000, 29 => 135_000, 30 => 155_000
    }.transform_keys { |cr| cr.to_r }.freeze

    # Returns the XP for +cr+ (a Numeric), or nil when the CR is unknown or ambiguous.
    def self.xp_for(cr)
      return nil if cr.nil?

      TABLE[cr.to_r.rationalize(Rational(1, 1000))]
    end
  end
end

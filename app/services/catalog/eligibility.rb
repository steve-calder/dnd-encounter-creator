module Catalog
  # Decides whether a normalized record may be used for encounter generation. Pure.
  module Eligibility
    module_function

    # Returns every reason the record is excluded; an empty list means eligible.
    def reasons(attrs)
      reasons = []
      reasons << "cr_unresolved" if attrs[:challenge_rating].nil?
      if attrs[:xp].nil?
        reasons << "xp_unresolved"
      elsif attrs[:xp].zero?
        reasons << "xp_zero"
      end
      reasons << "incomplete_stat_block" unless complete_stat_block?(attrs)
      reasons
    end

    # Actions are not required: some complete records (e.g. Frog) have none.
    def complete_stat_block?(attrs)
      attrs[:armor_class].present? &&
        attrs[:hit_points].present? &&
        attrs[:speed].present? &&
        Monster::ABILITIES.all? { |ability| attrs.dig(:abilities, ability).is_a?(Integer) }
    end
  end
end

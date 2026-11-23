module MonstersHelper
  INELIGIBILITY_LABELS = {
    "cr_unresolved" => "Challenge rating is missing or not a number",
    "xp_unresolved" => "XP is missing and can't be derived from the challenge rating",
    "xp_zero" => "XP is 0",
    "incomplete_stat_block" => "Stat block is incomplete (AC, HP, speed, or ability scores missing)"
  }.freeze

  XP_SOURCE_LABELS = {
    "source" => "from the source data",
    "derived_from_cr" => "derived from the challenge rating"
  }.freeze

  DEFENSE_FIELDS = {
    saving_throws: "Saving Throws", skills: "Skills", vulnerabilities: "Vulnerabilities",
    resistances: "Resistances", immunities: "Immunities", condition_immunities: "Condition Immunities",
    senses: "Senses", languages: "Languages"
  }.freeze

  ENTRY_SECTIONS = {
    actions: "Actions", bonus_actions: "Bonus Actions", reactions: "Reactions", legendary_actions: "Legendary Actions"
  }.freeze

  def signed(number)
    number.negative? ? "−#{number.abs}" : "+#{number}"
  end

  def ability_modifier(score)
    signed(Monster.ability_modifier(score))
  end

  def challenge_rating_label(monster)
    monster.challenge_rating_display || "—"
  end

  def xp_label(monster)
    monster.xp.nil? ? "—" : number_with_delimiter(monster.xp)
  end

  def ineligibility_label(reason)
    INELIGIBILITY_LABELS.fetch(reason, reason.humanize)
  end

  def xp_source_label(monster)
    XP_SOURCE_LABELS[monster.xp_source]
  end

  # "Melee Weapon Attack: +9 to hit, reach 5 ft., one target. Hit: 3d10 + 6 piercing damage."
  # Returns nil for entries without structured attack data.
  def attack_summary(entry)
    return if entry["hit_bonus"].blank? && entry["damage"].blank?

    to_hit = entry["hit_bonus"].to_s =~ /\A[+-]?\d+\z/ ? "#{signed(entry["hit_bonus"].to_i)} to hit" : entry["hit_bonus"].presence&.then { "#{_1} to hit" }
    distance = entry["attack_range"] == "Ranged" ? "range" : "reach"
    reach = [ entry["reach"].presence&.then { "#{distance} #{_1}" }, entry["target"] ].compact_blank.join(", ")
    hit = [ damage_text(entry["damage"], entry["damage_type"]), damage_text(entry["damage_2"], entry["damage_2_type"]) ].compact
    kind = [ entry["attack_range"], entry["attack_type"] || "Attack" ].compact_blank.join(" ")

    summary = "#{kind}: #{[ to_hit, reach ].compact_blank.join(", ")}."
    summary += " Hit: #{hit.join(" plus ")}." if hit.any?
    summary
  end

  def spell_level_label(level)
    level == "cantrips" ? "Cantrips (at will)" : "#{level} level"
  end

  private
    def damage_text(damage, type)
      return if damage.blank?

      [ damage, type, "damage" ].compact_blank.join(" ")
    end
end

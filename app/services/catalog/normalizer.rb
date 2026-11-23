require "digest"

module Catalog
  # Turns one verbatim upstream record into Monster attributes. Pure: no I/O.
  module Normalizer
    # Bump when parsing changes so re-import updates records whose source is unchanged.
    VERSION = 1

    ABILITY_KEYS = { "str" => "STR", "dex" => "DEX", "con" => "CON", "int" => "INT", "wis" => "WIS", "cha" => "CHA" }.freeze

    TEXT_FIELDS = {
      saving_throws: "Saving Throws", skills: "Skills", immunities: "Immunities",
      condition_immunities: "Condition Immunities", resistances: "Resistances",
      vulnerabilities: "Vulnerabilities", senses: "Senses", languages: "Languages"
    }.freeze

    ENTRY_LISTS = {
      traits: "data-Traits", actions: "data-Actions", bonus_actions: "data-Bonus Actions",
      reactions: "data-Reactions", legendary_actions: "data-Legendary Actions"
    }.freeze

    ENTRY_KEY_NAMES = { "Type Attack" => "attack_type", "Type" => "attack_range" }.freeze

    ROLL20_LEAD_INS = [
      /\AThese D&D 5E Free Basic Rules only contain .*?to fight!\s*/m,
      /\AThis monster appears in the Dungeons & Dragons Player's Handbook 2024\.\s*/
    ].freeze

    # The prose description repeats the stat block from the first section marker on.
    SECTION_MARKER = /(?:\A|\s)(?:Traits|Actions) /

    module_function

    def call(raw)
      props = raw.fetch("properties", {})
      cr = challenge_rating(props)
      xp, xp_source = experience(props, cr)

      {
        name: raw["name"],
        book: raw["book"],
        publisher: raw["publisher"],
        size: text(props["Size"]),
        creature_type: text(props["Type"]),
        alignment: text(props["Alignment"]),
        challenge_rating: cr&.to_f,
        challenge_rating_display: text(props["Challenge Rating"]),
        xp: xp,
        xp_source: xp_source,
        armor_class: integer(props["data-AcNum"]) || leading_integer(props["AC"]),
        armor_class_display: text(props["AC"]),
        hit_points: integer(props["data-HpNum"]) || leading_integer(props["HP"]),
        hit_points_display: text(props["HP"]),
        speed: text(props["Speed"]),
        abilities: ABILITY_KEYS.transform_values { |key| integer(props[key]) },
        **TEXT_FIELDS.transform_values { |key| text(props[key]) },
        **ENTRY_LISTS.transform_values { |key| entries(props[key]) },
        spells: spells(props["data-Spells"]),
        lore: lore(raw["description"]),
        source: raw,
        content_hash: content_hash(raw)
      }
    end

    # Returns a Rational, or nil when the CR is missing, non-numeric ("None"), or
    # disagrees with the source's own numeric CR.
    def challenge_rating(props)
      value = props["Challenge Rating"]
      cr =
        case value
        when Integer then Rational(value)
        when Float then value.to_r.rationalize(Rational(1, 1000))
        when %r{\A\s*(\d+)\s*/\s*(\d+)\s*\z} then Rational($1.to_i, $2.to_i)
        when /\A\s*\d+\s*\z/ then Rational(value.to_i)
        end
      return nil if cr.nil?

      check = props["data-CrNum"]
      return nil if check && check.to_r.rationalize(Rational(1, 1000)) != cr

      cr
    end

    def experience(props, cr)
      source_xp = integer(props["data-XP"])
      return [ source_xp, "source" ] if source_xp

      derived = CrXp.xp_for(cr)
      derived ? [ derived, "derived_from_cr" ] : [ nil, nil ]
    end

    def entries(json)
      parsed = parse_json(json)
      return [] unless parsed.is_a?(Array)

      parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)

        entry.to_h do |key, value|
          [ ENTRY_KEY_NAMES.fetch(key) { key.downcase.tr(" ", "_") }, value.is_a?(String) ? value.strip : value ]
        end
      end
    end

    def spells(json)
      parsed = parse_json(json)
      parsed.is_a?(Hash) && parsed["spells"].is_a?(Hash) ? parsed["spells"] : nil
    end

    def lore(description)
      text = description.to_s.dup
      ROLL20_LEAD_INS.each { |pattern| text.sub!(pattern, "") }
      text = text.split(SECTION_MARKER, 2).first.to_s.strip
      text.presence
    end

    def content_hash(raw)
      Digest::SHA256.hexdigest("#{VERSION}:#{JSON.generate(canonical(raw))}")
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [ key, canonical(value[key]) ] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def integer(value)
      case value
      when Integer then value
      when /\A\s*-?[\d,]+\s*\z/ then value.delete(",").to_i
      end
    end

    def leading_integer(value)
      value.is_a?(Integer) ? value : value.to_s[/\A\s*(\d+)/, 1]&.to_i
    end

    def text(value)
      value.nil? ? nil : value.to_s.strip.presence
    end

    def parse_json(json)
      json.is_a?(String) ? JSON.parse(json) : nil
    rescue JSON::ParserError
      nil
    end
  end
end

module Catalog
  # Builds the short plain-text description of a monster that is embedded for
  # vector search and indexed for keyword search. Pure and deterministic.
  #
  #   Giant Shark. Huge beast, Unaligned.
  #   Movement: Swim 50 ft.
  #   Senses: Blindsight 60 Ft.
  #   Traits: Blood Frenzy: The shark has advantage on... Water Breathing: ...
  #   Actions: Bite.
  #   A giant shark is 30 feet long and normally found in deep oceans...
  module SearchDocument
    MAX_LENGTH = 2_000
    ENTRY_DESCRIPTION_LENGTH = 160

    # Roll20 sheet macros such as @{npc_pb} and [[2d6]] carry no meaning for search.
    MACROS = /@\{[^}]*\}|\[\[[^\]]*\]\]/

    module_function

    # attrs: normalized monster attributes (Catalog::Normalizer output) with symbol keys.
    def call(attrs)
      head = [
        header(attrs),
        line("Movement", attrs[:speed]),
        line("Senses", attrs[:senses]),
        line("Traits", entries(attrs[:traits], describe_all: true)),
        line("Actions", entries(attrs[:actions], describe_all: false))
      ].compact.join("\n")
      head = truncate(head, MAX_LENGTH)

      lore = clean(attrs[:lore])
      return head if lore.blank?

      room = MAX_LENGTH - head.length - 1
      room >= 20 ? "#{head}\n#{truncate(lore, room)}" : head
    end

    def header(attrs)
      kind = [ attrs[:size], attrs[:creature_type] ].compact_blank.join(" ")
      description = [ kind, attrs[:alignment] ].compact_blank.join(", ")
      [ "#{clean(attrs[:name])}.", description.presence && "#{clean(description)}." ].compact.join(" ")
    end

    def line(label, value)
      value = clean(value)
      value.present? ? "#{label}: #{value.delete_suffix(".")}." : nil
    end

    # Traits keep a short description. Attack actions contribute only their name;
    # other actions (Multiattack, Breath Weapon, ...) keep a short description.
    def entries(list, describe_all:)
      Array(list).filter_map do |entry|
        name = clean(entry["name"])
        next if name.blank?

        attack = entry["hit_bonus"].present? || entry["damage"].present?
        description = clean(entry["desc"]) if describe_all || !attack
        description.present? ? "#{name}: #{truncate(description, ENTRY_DESCRIPTION_LENGTH).delete_suffix(".")}." : "#{name}."
      end.join(" ")
    end

    def clean(text)
      text.to_s.gsub(MACROS, "").gsub(/\(\s*\)/, "").gsub(/[*_]/, "").gsub(/\s+/, " ").strip
    end

    def truncate(text, length)
      text.truncate(length, separator: " ", omission: "...")
    end
  end
end

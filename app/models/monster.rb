# A catalog monster imported from the committed SRD dataset (db/data/srd_monsters.json).
# Populated only by Catalog::Importer; see app/services/catalog/.
class Monster
  include Mongoid::Document

  store_in collection: "monsters"

  # Stable, readable ID such as "srd-2014--giant-shark" (Catalog::RecordId).
  field :_id, type: String, overwrite: true

  field :name, type: String
  field :book, type: String
  field :publisher, type: String

  field :size, type: String
  field :creature_type, type: String
  field :alignment, type: String

  field :challenge_rating, type: Float
  field :challenge_rating_display, type: String
  field :xp, type: Integer
  field :xp_source, type: String # "source" or "derived_from_cr"

  field :armor_class, type: Integer
  field :armor_class_display, type: String
  field :hit_points, type: Integer
  field :hit_points_display, type: String
  field :speed, type: String
  field :abilities, type: Hash # { "str" => 23, ... }

  field :saving_throws, type: String
  field :skills, type: String
  field :immunities, type: String
  field :condition_immunities, type: String
  field :resistances, type: String
  field :vulnerabilities, type: String
  field :senses, type: String
  field :languages, type: String

  field :traits, type: Array, default: []
  field :actions, type: Array, default: []
  field :bonus_actions, type: Array, default: []
  field :reactions, type: Array, default: []
  field :legendary_actions, type: Array, default: []
  field :spells, type: Hash
  field :lore, type: String

  field :eligible, type: Mongoid::Boolean, default: false
  field :ineligibility_reasons, type: Array, default: []

  # The upstream record, verbatim.
  field :source, type: Hash
  field :content_hash, type: String
  field :source_revision, type: String
  field :source_checksum, type: String

  index({ eligible: 1 })
  index({ xp: 1 })
  index({ name: 1 })

  ABILITIES = %w[ str dex con int wis cha ].freeze

  def self.ability_modifier(score)
    (score - 10).div(2)
  end
end

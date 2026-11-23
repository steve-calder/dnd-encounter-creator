class MonstersController < ApplicationController
  LIST_FIELDS = %i[ name book size creature_type challenge_rating challenge_rating_display xp eligible ].freeze

  def index
    @query = params[:q].to_s.strip
    monsters = Monster.only(*LIST_FIELDS).order_by(name: :asc, book: :asc)
    # Escaped so the filter is a literal, case-insensitive substring match.
    monsters = monsters.where(name: /#{Regexp.escape(@query)}/i) if @query.present?
    @monsters = monsters.to_a
  end

  # Unknown IDs raise Mongoid::Errors::DocumentNotFound, which Mongoid's railtie maps to 404.
  def show
    @monster = Monster.find(params[:id])
  end
end

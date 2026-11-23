module Catalog
  # Prints vector and keyword search results side by side, to judge whether
  # vector retrieval surfaces better candidates for a scene (design doc,
  # "Acceptance example"). Used by bin/rails catalog:compare_search.
  class SearchComparison
    # max_xp 2,250 is the Moderate budget for three level-5 PCs, the largest
    # individual monster that could fit the boat example.
    MAX_XP = 2_250
    TOP = 8

    SCENES = {
      "Boat in rough seas" => "Three level-5 PCs are on a boat and encountering a challenge of sea creatures in rough seas. " \
        "The PCs are a fighter, wizard, and druid. The goal is to survive en route to their destination.",
      "Crypt" => "Undead rise from a crypt beneath a ruined chapel as the party searches the tombs.",
      "Forest road ambush" => "Wolves and goblins ambush travelers on a narrow forest road at dusk.",
      "Frozen mountain pass" => "A blizzard sweeps a frozen mountain pass while something hunts the party in the snow.",
      "Volcanic cave" => "Deep in a volcanic cave, rivers of lava and choking smoke hide fire-loving creatures."
    }.freeze

    def initialize(search: MonsterSearch.new, io: $stdout)
      @search = search
      @io = io
    end

    def run(scenes = SCENES, max_xp: MAX_XP)
      scenes.each { |title, query| compare(title, query, max_xp: max_xp) }
    end

    def compare(title, query, max_xp: MAX_XP)
      vector = @search.vector(query: query, max_xp: max_xp, limit: TOP)
      keyword = @search.keyword(query: query, max_xp: max_xp, limit: TOP)

      @io.puts "== #{title} (max #{max_xp} XP)"
      @io.puts "   #{query}"
      @io.puts format("   %-3s %-40s %s", "#", "VECTOR", "KEYWORD")
      [ vector.size, keyword.size, 1 ].max.times do |i|
        @io.puts format("   %-3d %-40s %s", i + 1, cell(vector[i]), cell(keyword[i]))
      end
      @io.puts
    end

    private
      def cell(candidate)
        return "-" unless candidate

        "#{candidate.name} (#{candidate.xp} XP, #{format("%.3f", candidate.score)})"
      end
  end
end

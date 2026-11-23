module Catalog
  # Finds catalog monsters for a described scene. Structured filters (eligible,
  # max individual XP, embedding model) are applied first; vector similarity ranks
  # what remains. Results are compact summaries plus IDs, never full stat blocks.
  #
  #   Catalog::MonsterSearch.vector(query: "sea creatures attacking a ship", max_xp: 2250)
  #   Catalog::MonsterSearch.keyword(query: "shark", max_xp: 2250)  # comparison baseline
  class MonsterSearch
    DEFAULT_LIMIT = 10
    MAX_LIMIT = 25

    Candidate = Data.define(:id, :name, :book, :size_type, :challenge_rating, :xp, :movement, :traits, :score)

    PROJECTION = {
      name: 1, book: 1, size: 1, creature_type: 1, challenge_rating_display: 1, xp: 1, speed: 1, "traits.name": 1
    }.freeze

    def self.vector(query:, **options) = new(**options.slice(:collection, :config, :client)).vector(query: query, **options.slice(:max_xp, :limit))
    def self.keyword(query:, **options) = new(**options.slice(:collection, :config)).keyword(query: query, **options.slice(:max_xp, :limit))

    def initialize(collection: Monster.collection, config: EmbeddingConfig.current, client: nil)
      @collection = collection
      @config = config
      @client = client
    end

    def vector(query:, max_xp: nil, limit: DEFAULT_LIMIT)
      limit = clamp(limit)
      require_index!(SearchIndexes::VECTOR_INDEX)
      unless collection.find(embedding_model: config.model).limit(1).first
        raise SearchUnavailable, "No monsters have embeddings from #{config.model} yet. Run bin/rails catalog:embed."
      end

      filter = { eligible: true, embedding_model: config.model }
      filter[:xp] = { "$lte" => max_xp } if max_xp

      run([
        { "$vectorSearch" => {
          index: SearchIndexes::VECTOR_INDEX, path: "embedding", queryVector: query_vector(query),
          numCandidates: [ limit * 20, 200 ].max, limit: limit, filter: filter
        } },
        { "$project" => PROJECTION.merge(score: { "$meta" => "vectorSearchScore" }) }
      ])
    end

    def keyword(query:, max_xp: nil, limit: DEFAULT_LIMIT)
      limit = clamp(limit)
      require_index!(SearchIndexes::TEXT_INDEX)

      filters = [ { equals: { path: "eligible", value: true } } ]
      filters << { range: { path: "xp", lte: max_xp } } if max_xp

      run([
        { "$search" => {
          index: SearchIndexes::TEXT_INDEX,
          compound: { must: [ { text: { query: query, path: %w[ name search_document ] } } ], filter: filters }
        } },
        { "$limit" => limit },
        { "$project" => PROJECTION.merge(score: { "$meta" => "searchScore" }) }
      ])
    end

    private
      attr_reader :collection, :config

      def client
        @client ||= Ollama::Client.new(base_url: config.ollama_url)
      end

      def clamp(limit)
        limit.to_i.clamp(1, MAX_LIMIT)
      end

      def require_index!(name)
        index = SearchIndexes.new(collection: collection, config: config).current_indexes[name]
        if index.nil?
          raise SearchUnavailable, "Search index #{name} is missing on #{collection.namespace}. Run bin/rails catalog:search_indexes."
        end
        return if index["queryable"]

        raise SearchUnavailable, "Search index #{name} is not queryable yet (status #{index["status"]}). " \
          "Wait for it to finish building, or run bin/rails catalog:search_indexes to wait."
      end

      def query_vector(query)
        vector = client.embed(model: config.model, inputs: [ config.query_input(query) ]).first
        return vector if vector.is_a?(Array) && vector.size == config.dimensions

        raise SearchUnavailable, "#{config.model} returned a #{vector.try(:size).inspect}-dimension query vector, " \
          "but EMBEDDING_DIMENSIONS is #{config.dimensions}."
      end

      def run(pipeline)
        collection.aggregate(pipeline).map do |doc|
          Candidate.new(
            id: doc["_id"],
            name: doc["name"],
            book: doc["book"],
            size_type: [ doc["size"], doc["creature_type"] ].compact.join(" "),
            challenge_rating: doc["challenge_rating_display"],
            xp: doc["xp"],
            movement: doc["speed"],
            traits: Array(doc["traits"]).filter_map { |trait| trait["name"] },
            score: doc["score"].to_f.round(4)
          )
        end
      end
  end
end

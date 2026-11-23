module Catalog
  # Owns the Atlas Search index definitions for the monsters collection and
  # applies them idempotently to whatever database Rails points at (dev, test
  # workers, CI). Replaces the old Docker init script, which ran only once.
  #
  #   Catalog::SearchIndexes.new.ensure!  # => { "monsters_vector_index" => :updated, "monsters_text_index" => :unchanged }
  class SearchIndexes
    VECTOR_INDEX = "monsters_vector_index".freeze
    TEXT_INDEX = "monsters_text_index".freeze

    class Failed < StandardError; end
    class Timeout < StandardError; end

    def initialize(collection: Monster.collection, config: EmbeddingConfig.current)
      @collection = collection
      @config = config
    end

    def definitions
      {
        VECTOR_INDEX => { type: "vectorSearch", definition: { "fields" => [
          { "type" => "vector", "path" => "embedding", "numDimensions" => config.dimensions, "similarity" => "cosine" },
          { "type" => "filter", "path" => "eligible" },
          { "type" => "filter", "path" => "xp" },
          { "type" => "filter", "path" => "challenge_rating" },
          { "type" => "filter", "path" => "embedding_model" }
        ] } },
        TEXT_INDEX => { type: "search", definition: { "mappings" => { "dynamic" => false, "fields" => {
          "name" => { "type" => "string" },
          "search_document" => { "type" => "string" },
          "eligible" => { "type" => "boolean" },
          "xp" => { "type" => "number" }
        } } } }
      }
    end

    # Creates missing indexes and updates ones whose definition differs.
    # Returns { index name => :created | :updated | :unchanged }.
    def ensure!(wait: true, timeout: 120)
      ensure_collection
      existing = current_indexes

      statuses = definitions.to_h do |name, spec|
        index = existing[name]
        status =
          if index.nil?
            collection.search_indexes.create_one(spec[:definition], name: name, type: spec[:type])
            :created
          elsif !matches?(spec[:definition], index["latestDefinition"])
            update(name, spec)
            :updated
          else
            :unchanged
          end
        [ name, status ]
      end

      wait_until_ready(timeout) if wait
      statuses
    end

    # True when every desired index exists, is queryable, and serves its current definition.
    def ready?
      existing = current_indexes
      definitions.all? do |name, spec|
        index = existing[name]
        raise Failed, "search index #{name} failed to build: #{index["message"]}" if index && index["status"] == "FAILED"

        index && index["queryable"] && index["status"] == "READY" && matches?(spec[:definition], index["latestDefinition"])
      end
    end

    def current_indexes
      collection.search_indexes.to_a.index_by { |index| index["name"] }
    rescue Mongo::Error::OperationFailure => e
      raise unless e.message.include?("NamespaceNotFound") || e.code == 26

      {}
    end

    private
      attr_reader :collection, :config

      def ensure_collection
        return if collection.database.collection_names.include?(collection.name)

        collection.create
      rescue Mongo::Error::OperationFailure => e
        raise unless e.code == 48 # NamespaceExists: created concurrently
      end

      # Atlas updates vector indexes in place, but mongodb-atlas-local (8.0) rejects
      # updateSearchIndex for vectorSearch indexes ("mappings" is required). There,
      # drop and recreate under the same name; the collection and documents are untouched.
      def update(name, spec)
        collection.search_indexes.update_one(spec[:definition], name: name)
      rescue Mongo::Error::OperationFailure => e
        raise unless spec[:type] == "vectorSearch" && e.message.include?("mappings")

        collection.search_indexes.drop_one(name: name)
        wait_for { !current_indexes.key?(name) }
        collection.search_indexes.create_one(spec[:definition], name: name, type: spec[:type])
      end

      def wait_for(timeout = 30)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        until yield
          raise Timeout, "timed out after #{timeout}s waiting on search indexes for #{collection.namespace}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.25
        end
      end

      def wait_until_ready(timeout)
        wait_for(timeout) { ready? }
      end

      # The server adds defaults (e.g. indexOptions on string fields), so a
      # definition matches when everything we specify is present with the same value.
      def matches?(desired, actual)
        case desired
        when Hash
          actual.is_a?(Hash) && desired.all? { |key, value| actual.key?(key.to_s) && matches?(value, actual[key.to_s]) }
        when Array
          return false unless actual.is_a?(Array) && actual.size == desired.size

          sort = ->(items) { items.sort_by { |item| item.is_a?(Hash) ? [ item["path"].to_s, item["type"].to_s ] : [ item.to_s, "" ] } }
          sort.(desired).zip(sort.(actual)).all? { |d, a| matches?(d, a) }
        when Numeric
          actual.is_a?(Numeric) && actual == desired
        else
          actual == desired
        end
      end
  end
end

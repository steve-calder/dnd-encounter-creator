# Helpers for tests that run real $vectorSearch / $search against mongot in the
# per-worker test database. Search indexes are provisioned once per test process;
# documents become searchable asynchronously, so assertions poll with a timeout.
module SearchIndexHelper
  DIMENSIONS = 768
  CONFIG = Catalog::EmbeddingConfig.new(model: "test-model", dimensions: DIMENSIONS, ollama_url: "http://ollama.invalid")

  class << self
    attr_accessor :provisioned_database
  end

  # Answers query embeddings from a fixed table: query text => vector.
  class StubQueryClient
    def initialize(vectors) = @vectors = vectors

    def embed(model:, inputs:)
      inputs.map { |input| @vectors.fetch(input) { raise ArgumentError, "no stub vector for query #{input.inspect}" } }
    end
  end

  def ensure_search_indexes!
    database = Monster.collection.database.name
    return if SearchIndexHelper.provisioned_database == database

    Catalog::SearchIndexes.new(config: CONFIG).ensure!(timeout: 90)
    SearchIndexHelper.provisioned_database = database
  end

  def one_hot(position)
    Array.new(DIMENSIONS, 0.0).tap { |vector| vector[position] = 1.0 }
  end

  # Gives every catalog record a distinct one-hot embedding from "test-model".
  # Returns { id => vector }.
  def embed_catalog_with_fixed_vectors!
    Monster.order_by(_id: :asc).pluck(:_id).each_with_index.to_h do |id, position|
      vector = one_hot(position)
      Monster.collection.update_one({ _id: id }, { "$set" => { embedding: vector, embedding_model: CONFIG.model } })
      [ id, vector ]
    end
  end

  # Re-runs the block until it returns truthy (mongot indexes writes asynchronously).
  def eventually(timeout: 30, message: "condition was not met")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result
      flunk "#{message} within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.2
    end
  end
end

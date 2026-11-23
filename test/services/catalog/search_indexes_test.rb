require "test_helper"

# Runs against real mongot in the per-worker test database, each test on its own
# throwaway collection so index state never leaks between tests.
class Catalog::SearchIndexesTest < ActiveSupport::TestCase
  CONFIG = Catalog::EmbeddingConfig.new(model: "test-model", dimensions: 768, ollama_url: "http://ollama.invalid")

  setup do
    @collection = Monster.collection.database["search_indexes_test_#{SecureRandom.hex(4)}"]
    @indexes = Catalog::SearchIndexes.new(collection: @collection, config: CONFIG)
  end

  teardown { @collection.drop }

  test "fresh collection: both indexes are created and become queryable" do
    statuses = @indexes.ensure!(timeout: 60)

    assert_equal({ "monsters_vector_index" => :created, "monsters_text_index" => :created }, statuses)
    assert @indexes.ready?
    vector = @indexes.current_indexes["monsters_vector_index"]
    assert_equal "vectorSearch", vector["type"]
    assert_includes vector["latestDefinition"]["fields"], { "type" => "filter", "path" => "embedding_model" }
  end

  test "second run reports both unchanged" do
    @indexes.ensure!(timeout: 60)

    assert_equal({ "monsters_vector_index" => :unchanged, "monsters_text_index" => :unchanged }, @indexes.ensure!(timeout: 60))
  end

  test "stale vector index is updated in place and documents are kept" do
    @collection.insert_one(_id: "srd-2014--giant-shark", name: "Giant Shark")
    @collection.search_indexes.create_one({ fields: [
      { type: "vector", path: "embedding", numDimensions: 1_536, similarity: "cosine" },
      { type: "filter", path: "challenge_rating" },
      { type: "filter", path: "environment" }
    ] }, name: "monsters_vector_index", type: "vectorSearch")

    statuses = @indexes.ensure!(timeout: 60)

    assert_equal :updated, statuses["monsters_vector_index"]
    assert_equal :created, statuses["monsters_text_index"]
    fields = @indexes.current_indexes["monsters_vector_index"]["latestDefinition"]["fields"]
    assert_equal 768, fields.find { |f| f["type"] == "vector" }["numDimensions"]
    assert_equal %w[ challenge_rating eligible embedding_model xp ], fields.select { |f| f["type"] == "filter" }.map { |f| f["path"] }.sort
    assert_equal 1, @collection.count_documents
  end
end

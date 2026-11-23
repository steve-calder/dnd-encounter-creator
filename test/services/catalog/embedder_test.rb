require "test_helper"

class Catalog::EmbedderTest < ActiveSupport::TestCase
  # Stands in for Ollama::Client: returns fixed vectors and records each call.
  class StubClient
    attr_reader :calls

    def initialize(dimensions:, fail_on_call: nil, error: Ollama::Error.new("boom"))
      @dimensions = dimensions
      @fail_on_call = fail_on_call
      @error = error
      @calls = []
    end

    def embed(model:, inputs:)
      @calls << { model: model, inputs: inputs }
      raise @error if @calls.size == @fail_on_call

      inputs.map { |input| Array.new(@dimensions) { |i| ((input.sum + i) % 97) / 97.0 } }
    end
  end

  setup do
    Catalog::Importer.new(dataset: Catalog::Dataset.load(srd_fixture_path)).call
    @count = Monster.count
  end

  def config(model: "test-model", dimensions: 8)
    Catalog::EmbeddingConfig.new(model: model, dimensions: dimensions, ollama_url: "http://ollama.invalid")
  end

  def embed(client, config: self.config)
    Catalog::Embedder.new(config: config, client: client).call
  end

  test "first run embeds every record with model, input hash, and vector" do
    report = embed(client = StubClient.new(dimensions: 8))

    assert_equal @count, report.embedded
    assert_equal 0, report.skipped
    shark = Monster.find("srd-2014--giant-shark")
    assert_equal 8, shark.embedding.size
    assert_equal "test-model", shark.embedding_model
    assert_equal 64, shark.embedding_input_hash.size
    assert shark.embedded_at
    assert_equal [ "test-model" ], client.calls.map { |c| c[:model] }.uniq
  end

  test "the exact templated input is what gets hashed" do
    config = self.config(model: "embeddinggemma")
    embedder = Catalog::Embedder.new(config: config, client: StubClient.new(dimensions: 8))
    embedder.call
    shark = Monster.find("srd-2014--giant-shark")

    expected_input = "title: Giant Shark | text: #{shark.search_document}"
    assert_equal embedder.input_hash(expected_input), shark.embedding_input_hash
  end

  test "second run skips everything and makes no model calls" do
    embed(StubClient.new(dimensions: 8))
    client = StubClient.new(dimensions: 8)
    report = embed(client)

    assert_equal 0, report.embedded
    assert_equal @count, report.skipped
    assert_empty client.calls
  end

  test "a model change re-embeds every record" do
    embed(StubClient.new(dimensions: 8))
    report = embed(StubClient.new(dimensions: 8), config: config(model: "other-model"))

    assert_equal @count, report.embedded
    assert_equal [ "other-model" ], Monster.distinct(:embedding_model)
  end

  test "a changed search document re-embeds only that record" do
    embed(StubClient.new(dimensions: 8))
    Monster.where(_id: "srd-2014--knight").update_all(search_document: "Knight. Changed.")
    client = StubClient.new(dimensions: 8)
    report = embed(client)

    assert_equal 1, report.embedded
    assert_equal @count - 1, report.skipped
    assert_equal [ "test-model" ], client.calls.map { |c| c[:model] }
    assert_match "Knight. Changed.", client.calls.sole[:inputs].sole
  end

  test "wrong-sized vectors are rejected and nothing is written" do
    error = assert_raises(Catalog::Embedder::DimensionMismatch) do
      embed(StubClient.new(dimensions: 1_024), config: config(dimensions: 768))
    end

    assert_match "768", error.message
    assert_match "1024", error.message
    assert_equal 0, Monster.where(:embedding.exists => true).count
  end

  test "a model failure keeps earlier batches and a rerun resumes" do
    stub_const(Catalog::Embedder, :BATCH_SIZE, 3) do
      assert_raises(Ollama::Error) { embed(StubClient.new(dimensions: 8, fail_on_call: 2)) }
      assert_equal 3, Monster.where(:embedding.exists => true).count

      report = embed(StubClient.new(dimensions: 8))
      assert_equal @count - 3, report.embedded
      assert_equal 3, report.skipped
    end
  end

  test "records without a search document must be imported first" do
    Monster.where(_id: "srd-2014--frog").update_all(search_document: nil)

    error = assert_raises(Catalog::Embedder::MissingSearchDocuments) { embed(StubClient.new(dimensions: 8)) }
    assert_match "catalog:import", error.message
  end
end

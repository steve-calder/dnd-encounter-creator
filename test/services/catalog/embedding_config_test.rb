require "test_helper"

class Catalog::EmbeddingConfigTest < ActiveSupport::TestCase
  test "defaults" do
    config = Catalog::EmbeddingConfig.current({})

    assert_equal "embeddinggemma", config.model
    assert_equal 768, config.dimensions
    assert_equal "http://localhost:11434", config.ollama_url
  end

  test "environment overrides" do
    config = Catalog::EmbeddingConfig.current(
      "EMBEDDING_MODEL" => "nomic-embed-text", "EMBEDDING_DIMENSIONS" => "1024", "OLLAMA_URL" => "http://ollama:11434"
    )

    assert_equal "nomic-embed-text", config.model
    assert_equal 1024, config.dimensions
    assert_equal "http://ollama:11434", config.ollama_url
  end

  test "rejects invalid dimensions" do
    assert_raises(ArgumentError) { Catalog::EmbeddingConfig.current("EMBEDDING_DIMENSIONS" => "0") }
    assert_raises(ArgumentError) { Catalog::EmbeddingConfig.current("EMBEDDING_DIMENSIONS" => "768.5") }
  end

  test "embeddinggemma prompt templates" do
    config = Catalog::EmbeddingConfig.current({})

    assert_equal "title: Giant Shark | text: A shark.", config.document_input(title: "Giant Shark", text: "A shark.")
    assert_equal "task: search result | query: sea monsters", config.query_input("sea monsters")
  end

  test "nomic prompt templates" do
    config = Catalog::EmbeddingConfig.current("EMBEDDING_MODEL" => "nomic-embed-text:latest")

    assert_equal "search_document: A shark.", config.document_input(title: "Giant Shark", text: "A shark.")
    assert_equal "search_query: sea monsters", config.query_input("sea monsters")
  end

  test "unknown models get no prefix" do
    config = Catalog::EmbeddingConfig.current("EMBEDDING_MODEL" => "mxbai-embed-large")

    assert_equal "A shark.", config.document_input(title: "Giant Shark", text: "A shark.")
    assert_equal "sea monsters", config.query_input("sea monsters")
  end
end

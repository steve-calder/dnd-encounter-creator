require "test_helper"

# Real $vectorSearch and $search against mongot, with fixed one-hot vectors and a
# stub query client: no Ollama.
class Catalog::MonsterSearchTest < ActiveSupport::TestCase
  include SearchIndexHelper

  SHARK = "srd-2014--giant-shark"
  SPIRIT = "srd-2024--draconic-spirit"

  setup do
    ensure_search_indexes!
    Catalog::Importer.new(dataset: Catalog::Dataset.load(srd_fixture_path)).call
    @vectors = embed_catalog_with_fixed_vectors!
    @client = SearchIndexHelper::StubQueryClient.new("shark" => @vectors[SHARK], "spirit" => @vectors[SPIRIT])
  end

  def vector_search(query, **options)
    Catalog::MonsterSearch.vector(query: query, config: SearchIndexHelper::CONFIG, client: @client, **options)
  end

  def ids(results) = results.map(&:id)

  test "smoke: a fixed vector is found through $vectorSearch" do
    results = eventually(message: "Giant Shark never became searchable") { vector_search("shark").presence }

    assert_includes ids(results), SHARK
  end

  test "results are ranked by similarity" do
    results = eventually { vector_search("shark").then { |r| r if r.first&.id == SHARK } }

    assert_equal SHARK, results.first.id
    assert_operator results.first.score, :>, results.second.score
  end

  test "ineligible records are excluded even as the closest match" do
    results = eventually { vector_search("spirit").presence }

    assert_not_includes ids(results), SPIRIT
    assert results.all? { |r| Monster.find(r.id).eligible }
  end

  test "maximum XP is applied before ranking" do
    results = eventually { vector_search("shark", max_xp: 1_000).presence }

    assert_not_includes ids(results), SHARK
    assert results.all? { |r| r.xp <= 1_000 }
  end

  test "embeddings from other models are excluded" do
    Monster.collection.update_one({ _id: SHARK }, { "$set" => { embedding_model: "other-model" } })

    results = eventually(message: "Giant Shark was still returned") { vector_search("shark").then { |r| r if r.any? && !ids(r).include?(SHARK) } }
    assert_not_includes ids(results), SHARK
  end

  test "limit is clamped to 25" do
    30.times do |i|
      Monster.collection.insert_one(_id: "test--filler-#{i}", name: "Filler #{i}", eligible: true, xp: 10,
        embedding: one_hot(700 + i % 60), embedding_model: SearchIndexHelper::CONFIG.model)
    end

    results = eventually(message: "fewer than 25 results") { vector_search("shark", limit: 100).then { |r| r if r.size >= 25 } }
    assert_equal 25, results.size
  end

  test "results are compact summaries" do
    shark = eventually { vector_search("shark").find { |r| r.id == SHARK } }

    assert_equal(
      { id: SHARK, name: "Giant Shark", book: "Free Basic Rules (2014)", size_type: "Huge beast", challenge_rating: "5",
        xp: 1_800, movement: "Swim 50 ft.", traits: [ "Blood Frenzy", "Water Breathing" ] },
      shark.to_h.except(:score)
    )
    assert_kind_of Float, shark.score
  end

  test "missing vector index names the provisioning task" do
    empty = Monster.collection.database["monster_search_no_index_#{SecureRandom.hex(4)}"]
    empty.create
    error = assert_raises(Catalog::SearchUnavailable) do
      Catalog::MonsterSearch.vector(query: "shark", collection: empty, config: SearchIndexHelper::CONFIG, client: @client)
    end

    assert_match "monsters_vector_index", error.message
    assert_match "catalog:search_indexes", error.message
  ensure
    empty&.drop
  end

  test "no embeddings for the configured model names the embedding task" do
    other = SearchIndexHelper::CONFIG.with(model: "never-embedded")
    error = assert_raises(Catalog::SearchUnavailable) do
      Catalog::MonsterSearch.vector(query: "shark", config: other, client: @client)
    end

    assert_match "never-embedded", error.message
    assert_match "catalog:embed", error.message
  end

  test "keyword search matches names and documents with the same filters" do
    search = ->(**options) { Catalog::MonsterSearch.keyword(query: "shark", config: SearchIndexHelper::CONFIG, **options) }
    results = eventually(message: "sharks never became searchable") { search.call.then { |r| r if (ids(r) & [ SHARK, "srd-2014--reef-shark" ]).size == 2 } }

    assert_equal SHARK, results.first.id
    assert results.all? { |r| Monster.find(r.id).eligible }
    assert_not_includes ids(search.call(max_xp: 1_000)), SHARK
  end
end

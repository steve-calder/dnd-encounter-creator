require "test_helper"

class Catalog::ImporterTest < ActiveSupport::TestCase
  def import(dataset = Catalog::Dataset.load(srd_fixture_path))
    Catalog::Importer.new(dataset: dataset).call
  end

  test "first import creates every record with provenance and eligibility" do
    report = import
    count = srd_fixture["monsters"].size

    assert_equal count, report.created
    assert_equal 0, report.updated
    assert_equal count, Monster.count
    assert_equal "649f7f964b20835852bff3659aa36875dd7c35df", report.commit
    assert_equal count - 1, report.eligible
    assert_equal 1, report.ineligible
    assert_equal({ "cr_unresolved" => 1, "xp_zero" => 1 }, report.ineligible_reasons)

    shark = Monster.find("srd-2014--giant-shark")
    assert shark.eligible
    assert_equal 1800, shark.xp
    assert_equal "649f7f964b20835852bff3659aa36875dd7c35df", shark.source_revision
    assert_equal raw_monster("Giant Shark"), shark.source

    spirit = Monster.find("srd-2024--draconic-spirit")
    assert_not spirit.eligible
    assert_equal [ "cr_unresolved", "xp_zero" ], spirit.ineligibility_reasons
  end

  test "same-name variants are stored separately" do
    import

    assert_equal [ "Free Basic Rules (2014)", "Free Basic Rules (2024)" ], Monster.where(name: "Ape").pluck(:book).sort
  end

  test "re-import is idempotent" do
    import
    ids = Monster.pluck(:_id).sort
    report = import

    assert_equal 0, report.created
    assert_equal 0, report.updated
    assert_equal srd_fixture["monsters"].size, report.unchanged
    assert_equal ids, Monster.pluck(:_id).sort
  end

  test "a changed source record is updated in place" do
    import
    changed = srd_fixture.deep_dup
    changed["monsters"].find { |m| m["name"] == "Giant Shark" }["properties"].merge!("HP" => "130 (12d12+52)", "data-HpNum" => 130)
    report = import(Catalog::Dataset.new(source: changed["source"], monsters: changed["monsters"]))

    assert_equal 1, report.updated
    assert_equal 130, Monster.find("srd-2014--giant-shark").hit_points
  end

  test "search document is stored" do
    import

    assert_match "Giant Shark. Huge beast", Monster.find("srd-2014--giant-shark").search_document
  end

  EMBEDDING_FIELDS = {
    embedding: [ 0.5, 0.25 ], embedding_model: "test-model", embedding_input_hash: "abc123", embedded_at: Time.utc(2026, 1, 1)
  }.freeze

  def embed_shark!
    Monster.collection.update_one({ _id: "srd-2014--giant-shark" }, { "$set" => EMBEDDING_FIELDS })
  end

  def shark_embedding_fields
    Monster.collection.find(_id: "srd-2014--giant-shark").first.slice(*EMBEDDING_FIELDS.keys.map(&:to_s)).symbolize_keys
  end

  test "unchanged re-import keeps embedding fields" do
    import
    embed_shark!
    import

    assert_equal EMBEDDING_FIELDS, shark_embedding_fields
  end

  test "updated re-import keeps embedding fields and updates normalized fields" do
    import
    embed_shark!
    changed = srd_fixture.deep_dup
    changed["monsters"].find { |m| m["name"] == "Giant Shark" }["properties"].merge!("HP" => "130 (12d12+52)", "data-HpNum" => 130)
    report = import(Catalog::Dataset.new(source: changed["source"], monsters: changed["monsters"]))

    assert_equal 1, report.updated
    assert_equal 130, Monster.find("srd-2014--giant-shark").hit_points
    assert_equal EMBEDDING_FIELDS, shark_embedding_fields
  end

  test "records missing from the dataset are reported as stale and kept" do
    Monster.create!(_id: "srd-2014--retired", name: "Retired")

    assert_equal [ "srd-2014--retired" ], import.stale_ids
    assert Monster.where(_id: "srd-2014--retired").exists?
  end

  test "an integrity failure writes nothing" do
    bad = srd_fixture.merge("monsters" => srd_fixture["monsters"].drop(1))

    assert_raises(Catalog::Dataset::Invalid) do
      import(Catalog::Dataset.new(source: bad["source"], monsters: bad["monsters"]))
    end
    assert_equal 0, Monster.count
  end

  test "an ID collision aborts before writing" do
    duplicated = srd_fixture["monsters"] + [ raw_monster("Giant Shark") ]
    source = srd_fixture["source"].merge("record_count" => duplicated.size)

    assert_raises(Catalog::Importer::DuplicateId) do
      import(Catalog::Dataset.new(source: source, monsters: duplicated))
    end
    assert_equal 0, Monster.count
  end
end

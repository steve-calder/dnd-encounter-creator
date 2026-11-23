require "test_helper"

class Catalog::DatasetTest < ActiveSupport::TestCase
  def write_dataset(document)
    file = Tempfile.new([ "dataset", ".json" ])
    file.write(JSON.generate(document))
    file.close
    @tempfiles = [ *@tempfiles, file ]
    file.path
  end

  teardown { @tempfiles&.each(&:unlink) }

  test "loads the header and records" do
    dataset = Catalog::Dataset.load(srd_fixture_path)

    assert_equal "649f7f964b20835852bff3659aa36875dd7c35df", dataset.commit
    assert_equal "cee519309b7241ed6cd45b2217f9e37e481d451aa3fd9ce251dfbd7a4ef302c7", dataset.sha256
    assert_equal srd_fixture["source"]["record_count"], dataset.monsters.size
  end

  test "the committed dataset is valid" do
    dataset = Catalog::Dataset.load

    assert_equal 379, dataset.monsters.size
    assert_equal [ "Free Basic Rules (2014)", "Free Basic Rules (2024)" ], dataset.source["books"]
  end

  test "rejects a missing header" do
    path = write_dataset("monsters" => srd_fixture["monsters"])

    error = assert_raises(Catalog::Dataset::Invalid) { Catalog::Dataset.load(path) }
    assert_includes error.message, "missing provenance header"
  end

  test "rejects a record count mismatch" do
    path = write_dataset(srd_fixture.merge("monsters" => srd_fixture["monsters"].drop(1)))
    expected = srd_fixture["source"]["record_count"]

    error = assert_raises(Catalog::Dataset::Invalid) { Catalog::Dataset.load(path) }
    assert_includes error.message, "header says #{expected} records, found #{expected - 1}"
  end
end

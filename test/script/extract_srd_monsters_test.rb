require "test_helper"
require Rails.root.join("script/extract_srd_monsters").to_s

class ExtractSrdMonstersTest < ActiveSupport::TestCase
  setup do
    @input = file_fixture("upstream_monsters_sample.json").to_s
    @sha256 = Digest::SHA256.file(@input).hexdigest
    @dir = Dir.mktmpdir
    @output = File.join(@dir, "srd_monsters.json")
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "keeps only records from the selected books, verbatim and sorted" do
    document = SrdMonsterExtractor.new(sha256: @sha256).run(input: @input, output: @output)
    names = document["monsters"].map { |m| [ m["book"], m["name"] ] }

    assert_equal [
      [ "Free Basic Rules (2014)", "Ape" ],
      [ "Free Basic Rules (2014)", "Zombie" ],
      [ "Free Basic Rules (2024)", "Ape" ]
    ], names
    assert_not_includes document["monsters"].map { |m| m["book"] }, "Tome of Beasts 2"

    upstream = JSON.parse(File.read(@input))
    assert_equal upstream[3], document["monsters"].first
  end

  test "writes a provenance header" do
    SrdMonsterExtractor.new(sha256: @sha256).run(input: @input, output: @output)
    source = JSON.parse(File.read(@output))["source"]

    assert_equal "nick-aschenbach/dnd-data", source["repository"]
    assert_equal SrdMonsterExtractor::COMMIT, source["commit"]
    assert_equal "data/monsters.json", source["path"]
    assert_equal @sha256, source["sha256"]
    assert_equal SrdMonsterExtractor::BOOKS, source["books"]
    assert_equal 3, source["record_count"]
  end

  test "output is byte-identical across runs" do
    extractor = SrdMonsterExtractor.new(sha256: @sha256)
    extractor.run(input: @input, output: @output)
    first = File.binread(@output)
    extractor.run(input: @input, output: @output)

    assert_equal first, File.binread(@output)
  end

  test "checksum mismatch aborts and leaves the existing output untouched" do
    File.write(@output, "existing")

    error = assert_raises(SrdMonsterExtractor::ChecksumMismatch) do
      SrdMonsterExtractor.new(sha256: "0" * 64).run(input: @input, output: @output)
    end

    assert_includes error.message, "0" * 64
    assert_includes error.message, @sha256
    assert_equal "existing", File.read(@output)
    assert_equal [ "srd_monsters.json" ], Dir.children(@dir)
  end
end

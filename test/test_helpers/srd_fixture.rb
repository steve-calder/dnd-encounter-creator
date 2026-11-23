# Access to test/fixtures/files/srd_monsters_sample.json, a trimmed copy of
# db/data/srd_monsters.json in the same header-plus-records format.
module SrdFixture
  def srd_fixture_path
    file_fixture("srd_monsters_sample.json").to_s
  end

  def srd_fixture
    @srd_fixture ||= JSON.parse(File.read(srd_fixture_path))
  end

  def raw_monster(name, book = "Free Basic Rules (2014)")
    srd_fixture["monsters"].find { |m| m["name"] == name && m["book"] == book } or
      raise ArgumentError, "#{name} (#{book}) is not in the SRD fixture"
  end
end

module Catalog
  # Loads the committed catalog dataset (db/data/srd_monsters.json), which
  # script/extract_srd_monsters.rb generates. No network access.
  class Dataset
    DEFAULT_PATH = Rails.root.join("db/data/srd_monsters.json")

    class Invalid < StandardError; end

    attr_reader :source, :monsters

    def self.load(path = DEFAULT_PATH)
      document = JSON.parse(File.read(path))
      raise Invalid, "#{path}: not a dataset document" unless document.is_a?(Hash)

      new(source: document["source"], monsters: document["monsters"], path: path)
    rescue JSON::ParserError => e
      raise Invalid, "#{path}: invalid JSON (#{e.message})"
    end

    def initialize(source:, monsters:, path: nil)
      raise Invalid, "#{path}: missing provenance header" unless source.is_a?(Hash) && source["record_count"].is_a?(Integer)
      raise Invalid, "#{path}: missing monsters list" unless monsters.is_a?(Array)
      unless monsters.size == source["record_count"]
        raise Invalid, "#{path}: header says #{source["record_count"]} records, found #{monsters.size}"
      end

      @source = source
      @monsters = monsters
    end

    def commit = source["commit"]
    def sha256 = source["sha256"]
  end
end

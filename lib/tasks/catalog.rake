namespace :catalog do
  desc "Import the committed SRD monster dataset (db/data/srd_monsters.json) into MongoDB"
  task import: :environment do
    puts Catalog::Importer.new.call
  rescue Catalog::Dataset::Invalid, Catalog::Importer::DuplicateId => e
    abort "Catalog import aborted, nothing written: #{e.message}"
  end

  desc "Create or update the monsters vector and text search indexes, then wait until they are queryable"
  task search_indexes: :environment do
    indexes = Catalog::SearchIndexes.new
    indexes.ensure!.each { |name, status| puts "#{name}: #{status}" }
    vector = indexes.current_indexes[Catalog::SearchIndexes::VECTOR_INDEX]
    dimensions = vector["latestDefinition"]["fields"].find { |f| f["type"] == "vector" }["numDimensions"]
    puts "Ready (#{dimensions}-dimension vectors)."
  rescue Catalog::SearchIndexes::Failed, Catalog::SearchIndexes::Timeout, Mongo::Error => e
    abort "Search index setup failed: #{e.message}"
  end

  desc 'Vector search the catalog: bin/rails "catalog:search[sea creatures attacking a ship,2250]"'
  task :search, [ :query, :max_xp ] => :environment do |_, args|
    abort 'Usage: bin/rails "catalog:search[<query>,<max_xp>]"' if args[:query].blank?

    max_xp = args[:max_xp].presence&.then { Integer(_1) }
    results = Catalog::MonsterSearch.vector(query: args[:query], max_xp: max_xp, limit: 10)
    puts "No eligible monsters matched." if results.empty?
    results.each_with_index do |c, i|
      puts format("%2d. %-32s %-26s CR %-4s %6d XP  score %.3f  %s", i + 1, c.name, c.book, c.challenge_rating, c.xp, c.score, c.id)
    end
  rescue Ollama::Error, Catalog::SearchUnavailable => e
    abort "Search failed: #{e.message}"
  end

  desc "Compare vector and keyword search side by side for the boat prompt and other scenes"
  task compare_search: :environment do
    Catalog::SearchComparison.new.run
  rescue Ollama::Error, Catalog::SearchUnavailable => e
    abort "Comparison failed: #{e.message}"
  end

  desc "Embed each monster's search document with the local Ollama model (skips unchanged records)"
  task embed: :environment do
    puts Catalog::Embedder.new.call
  rescue Ollama::Error, Catalog::Embedder::DimensionMismatch, Catalog::Embedder::MissingSearchDocuments => e
    abort "Embedding stopped: #{e.message}"
  end
end

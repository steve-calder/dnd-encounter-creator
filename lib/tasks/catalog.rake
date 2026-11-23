namespace :catalog do
  desc "Import the committed SRD monster dataset (db/data/srd_monsters.json) into MongoDB"
  task import: :environment do
    puts Catalog::Importer.new.call
  rescue Catalog::Dataset::Invalid, Catalog::Importer::DuplicateId => e
    abort "Catalog import aborted, nothing written: #{e.message}"
  end
end

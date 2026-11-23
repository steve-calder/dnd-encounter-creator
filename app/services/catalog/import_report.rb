module Catalog
  # Outcome of one Catalog::Importer run.
  ImportReport = Data.define(:commit, :sha256, :created, :updated, :unchanged, :eligible, :ineligible_reasons, :ineligible, :stale_ids) do
    def total = created + updated + unchanged

    def to_s
      lines = [
        "Catalog import from #{commit} (sha256 #{sha256})",
        "  created: #{created}, updated: #{updated}, unchanged: #{unchanged} (#{total} records)",
        "  eligible: #{eligible}, ineligible: #{ineligible}"
      ]
      ineligible_reasons.sort.each { |reason, count| lines << "    #{reason}: #{count}" }
      lines << "  stale (in database, not in dataset; left in place): #{stale_ids.join(", ")}" if stale_ids.any?
      lines.join("\n")
    end
  end
end

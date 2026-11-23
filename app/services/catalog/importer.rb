module Catalog
  # Imports every record in the committed dataset into the Monster collection.
  # Idempotent: upserts by stable ID and skips records whose content is unchanged.
  # Upserts use $set (replace: false) so fields the import does not own, such as
  # embeddings written by Catalog::Embedder, survive a re-import.
  class Importer
    class DuplicateId < StandardError; end

    def initialize(dataset: Dataset.load)
      @dataset = dataset
    end

    def call
      documents = build_documents
      existing = Monster.in(_id: documents.keys).pluck(:_id, :content_hash).to_h
      counts = Hash.new(0)

      documents.each do |id, attrs|
        status = if !existing.key?(id) then :created
        elsif existing[id] != attrs[:content_hash] then :updated
        else :unchanged
        end
        Monster.new(attrs).upsert(replace: false) unless status == :unchanged
        counts[status] += 1
      end

      report(documents, counts)
    end

    private
      attr_reader :dataset

      # Normalizes everything before writing, so a bad record aborts the run with
      # nothing written.
      def build_documents
        @dataset.monsters.each_with_object({}) do |raw, documents|
          id = RecordId.for(book: raw["book"], name: raw["name"])
          raise DuplicateId, "two dataset records map to ID #{id}" if documents.key?(id)

          attrs = Normalizer.call(raw)
          reasons = Eligibility.reasons(attrs)
          documents[id] = attrs.merge(
            _id: id,
            eligible: reasons.empty?,
            ineligibility_reasons: reasons,
            source_revision: dataset.commit,
            source_checksum: dataset.sha256
          )
        end
      end

      def report(documents, counts)
        ineligible = documents.values.reject { |attrs| attrs[:eligible] }

        ImportReport.new(
          commit: dataset.commit,
          sha256: dataset.sha256,
          created: counts[:created],
          updated: counts[:updated],
          unchanged: counts[:unchanged],
          eligible: documents.size - ineligible.size,
          ineligible: ineligible.size,
          ineligible_reasons: ineligible.flat_map { |attrs| attrs[:ineligibility_reasons] }.tally,
          stale_ids: Monster.nin(_id: documents.keys).pluck(:_id).sort
        )
      end
  end
end

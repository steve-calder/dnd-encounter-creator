require "digest"

module Catalog
  # Embeds each monster's search document with the configured local model.
  #
  # A record is skipped when its stored model and input hash match what would be
  # sent now, so re-running is cheap and only changed records are re-embedded.
  # Batches are validated before anything from them is written; a failure keeps
  # earlier batches, so a rerun resumes where it stopped.
  class Embedder
    BATCH_SIZE = 32

    Report = Data.define(:model, :dimensions, :embedded, :skipped) do
      def to_s
        "Embedded #{embedded} and skipped #{skipped} unchanged records with #{model} (#{dimensions} dimensions)."
      end
    end

    class DimensionMismatch < StandardError; end
    class MissingSearchDocuments < StandardError; end

    def initialize(config: EmbeddingConfig.current, client: nil)
      @config = config
      @client = client || Ollama::Client.new(base_url: config.ollama_url)
    end

    def call
      pending, skipped = partition_records
      pending.each_slice(BATCH_SIZE) { |batch| write(batch, embed(batch)) }

      Report.new(model: config.model, dimensions: config.dimensions, embedded: pending.size, skipped: skipped)
    end

    def input_hash(input)
      Digest::SHA256.hexdigest("#{config.model}\n#{input}")
    end

    private
      attr_reader :config, :client

      def partition_records
        records = Monster.only(:_id, :name, :search_document, :embedding_model, :embedding_input_hash).order_by(_id: :asc).to_a
        missing = records.count { |record| record.search_document.blank? }
        if missing.positive?
          raise MissingSearchDocuments, "#{missing} records have no search document; run bin/rails catalog:import first"
        end

        pending = []
        skipped = 0
        records.each do |record|
          input = config.document_input(title: record.name, text: record.search_document)
          hash = input_hash(input)
          if record.embedding_model == config.model && record.embedding_input_hash == hash
            skipped += 1
          else
            pending << { id: record.id, input: input, hash: hash }
          end
        end
        [ pending, skipped ]
      end

      def embed(batch)
        vectors = client.embed(model: config.model, inputs: batch.map { |item| item[:input] })
        unless vectors.is_a?(Array) && vectors.size == batch.size
          raise Ollama::Error, "#{config.model} returned #{vectors.try(:size).inspect} embeddings for #{batch.size} inputs"
        end

        wrong = vectors.find { |vector| !vector.is_a?(Array) || vector.size != config.dimensions }
        if wrong
          raise DimensionMismatch, "#{config.model} returned #{wrong.try(:size).inspect}-dimension vectors, but EMBEDDING_DIMENSIONS is " \
            "#{config.dimensions}. Set EMBEDDING_DIMENSIONS to the model's size and run bin/rails catalog:search_indexes."
        end

        vectors
      end

      def write(batch, vectors)
        now = Time.now.utc
        operations = batch.zip(vectors).map do |item, vector|
          { update_one: { filter: { _id: item[:id] }, update: { "$set" => {
            embedding: vector.map(&:to_f), embedding_model: config.model, embedding_input_hash: item[:hash], embedded_at: now
          } } } }
        end
        Monster.collection.bulk_write(operations, ordered: false)
      end
  end
end

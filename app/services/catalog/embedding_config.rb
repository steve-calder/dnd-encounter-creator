module Catalog
  # Embedding settings shared by the embedder, both searches, and the search
  # index definitions, so catalog and query vectors always come from the same
  # model with the same size. Services take a config argument (default
  # EmbeddingConfig.current) so tests can pass their own.
  EmbeddingConfig = Data.define(:model, :dimensions, :ollama_url) do
    def self.current(env = ENV)
      dimensions = env.fetch("EMBEDDING_DIMENSIONS", "768")
      unless dimensions.match?(/\A[1-9]\d*\z/)
        raise ArgumentError, "EMBEDDING_DIMENSIONS must be a positive integer, got #{dimensions.inspect}"
      end

      new(
        model: env.fetch("EMBEDDING_MODEL", "embeddinggemma"),
        dimensions: dimensions.to_i,
        ollama_url: env.fetch("OLLAMA_URL", "http://localhost:11434")
      )
    end

    # Text sent to the model for a catalog record.
    def document_input(title:, text:)
      case family
      when :embeddinggemma then "title: #{title} | text: #{text}"
      when :nomic then "search_document: #{text}"
      else text
      end
    end

    # Text sent to the model for a search query.
    def query_input(text)
      case family
      when :embeddinggemma then "task: search result | query: #{text}"
      when :nomic then "search_query: #{text}"
      else text
      end
    end

    private
      def family
        if model.start_with?("embeddinggemma") then :embeddinggemma
        elsif model.start_with?("nomic-embed-text") then :nomic
        end
      end
  end
end

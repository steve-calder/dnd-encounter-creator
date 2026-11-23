require "net/http"

module Ollama
  # Minimal client for the local Ollama HTTP API (stdlib only).
  class Client
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 120

    attr_reader :base_url

    def initialize(base_url: Catalog::EmbeddingConfig.current.ollama_url)
      @base_url = base_url.chomp("/")
    end

    # Returns one embedding (Array of Floats) per input, in order.
    def embed(model:, inputs:)
      body = post("/api/embed", { model: model, input: inputs }, model: model)
      embeddings = body["embeddings"]
      unless embeddings.is_a?(Array) && embeddings.size == inputs.size
        raise Error, "Ollama at #{base_url} returned #{embeddings.is_a?(Array) ? embeddings.size : "no"} embeddings for #{inputs.size} inputs (model #{model})"
      end

      embeddings
    end

    private
      def post(path, payload, model:)
        uri = URI.join("#{base_url}/", path.delete_prefix("/"))
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.post(uri.path, JSON.generate(payload), "Content-Type" => "application/json")
        end

        unless response.is_a?(Net::HTTPSuccess)
          detail = error_detail(response.body)
          raise Error, "Ollama at #{base_url} returned HTTP #{response.code} for model #{model}#{": #{detail}" if detail}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Ollama at #{base_url} returned invalid JSON for model #{model}: #{e.message}"
      rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
        raise Error, "Could not reach Ollama at #{base_url} (model #{model}): #{e.message}. Is Ollama running?"
      end

      def error_detail(body)
        JSON.parse(body.to_s)["error"]
      rescue JSON::ParserError
        body.to_s[0, 200].presence
      end
  end
end

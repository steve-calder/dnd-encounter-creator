module Ollama
  # Raised for any failure talking to Ollama. Messages name the URL and model so
  # the caller can show a recoverable error ("is Ollama running?").
  class Error < StandardError; end
end

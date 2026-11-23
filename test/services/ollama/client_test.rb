require "test_helper"
require "socket"

class Ollama::ClientTest < ActiveSupport::TestCase
  # A one-request HTTP server on a random local port that replies with a canned response
  # and records the request it received.
  def with_fake_ollama(status:, body:)
    server = TCPServer.new("127.0.0.1", 0)
    received = {}
    thread = Thread.new do
      socket = server.accept
      request_line = socket.gets
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        key, value = line.split(": ", 2)
        headers[key.downcase] = value.strip
      end
      received[:path] = request_line.split[1]
      received[:body] = JSON.parse(socket.read(headers["content-length"].to_i))
      reason = { 200 => "OK", 404 => "Not Found" }.fetch(status, "Error")
      socket.write("HTTP/1.1 #{status} #{reason}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
    yield "http://127.0.0.1:#{server.addr[1]}", received
  ensure
    thread&.join(5)
    server&.close
  end

  test "embed returns vectors and sends model and inputs" do
    with_fake_ollama(status: 200, body: { embeddings: [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ] }.to_json) do |url, received|
      vectors = Ollama::Client.new(base_url: url).embed(model: "embeddinggemma", inputs: [ "a", "b" ])

      assert_equal [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ], vectors
      assert_equal "/api/embed", received[:path]
      assert_equal({ "model" => "embeddinggemma", "input" => [ "a", "b" ] }, received[:body])
    end
  end

  test "connection refused names the URL and model" do
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] } # free port, now closed
    error = assert_raises(Ollama::Error) do
      Ollama::Client.new(base_url: "http://127.0.0.1:#{port}").embed(model: "embeddinggemma", inputs: [ "a" ])
    end

    assert_match "http://127.0.0.1:#{port}", error.message
    assert_match "embeddinggemma", error.message
  end

  test "model not found names the URL, model, and Ollama's error" do
    with_fake_ollama(status: 404, body: { error: "model \"nope\" not found, try pulling it first" }.to_json) do |url, _|
      error = assert_raises(Ollama::Error) { Ollama::Client.new(base_url: url).embed(model: "nope", inputs: [ "a" ]) }

      assert_match url, error.message
      assert_match "nope", error.message
      assert_match "404", error.message
      assert_match "not found", error.message
    end
  end

  test "malformed JSON names the URL and model" do
    with_fake_ollama(status: 200, body: "not json") do |url, _|
      error = assert_raises(Ollama::Error) { Ollama::Client.new(base_url: url).embed(model: "embeddinggemma", inputs: [ "a" ]) }

      assert_match url, error.message
      assert_match "embeddinggemma", error.message
    end
  end

  test "wrong number of embeddings is an error" do
    with_fake_ollama(status: 200, body: { embeddings: [ [ 0.1 ] ] }.to_json) do |url, _|
      assert_raises(Ollama::Error) { Ollama::Client.new(base_url: url).embed(model: "embeddinggemma", inputs: [ "a", "b" ]) }
    end
  end
end

require "net/http"

module Search
  # Text embeddings from the local Ollama server (https://github.com/ollama/ollama/blob/main/docs/api.md#generate-embeddings).
  # nomic-embed-text expects a task prefix: "search_document: " for indexed text, "search_query: " for questions.
  class Embedder
    DIMENSIONS = 768 # must match search_documents.embedding
    BATCH = 64

    def initialize(url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"), model: ENV.fetch("EMBED_MODEL", "nomic-embed-text"))
      @uri = URI.join(url, "/api/embed")
      @model = model
    end

    attr_reader :model

    def documents(texts) = embed(texts.map { |t| "search_document: #{t}" }, keep_alive: "5m")
    # Unload right away: a question embeds one short query, and keeping this model resident takes GPU memory the
    # chat model needs (on an 8 GB GPU it pushed most of a 27B model onto the CPU and slowed answers several-fold).
    def query(text) = embed([ "search_query: #{text}" ], keep_alive: 0).first

    private

    def embed(inputs, keep_alive:)
      inputs.each_slice(BATCH).flat_map do |batch|
        response = Net::HTTP.start(@uri.host, @uri.port, open_timeout: 5, read_timeout: 300) do |http|
          http.post(@uri.path, { model: @model, input: batch, keep_alive: }.to_json, "Content-Type" => "application/json")
        end
        data = JSON.parse(response.body)
        unless response.is_a?(Net::HTTPSuccess)
          raise Summaries::OllamaClient::Error, "Ollama embeddings #{response.code}: #{data['error']} (is `#{@model}` pulled?)"
        end

        data["embeddings"]
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, SocketError => e
      raise Summaries::OllamaClient::Unavailable, "Can't reach Ollama at #{@uri.host}:#{@uri.port} (#{e.class.name.demodulize}). Is `ollama serve` running?"
    end
  end
end

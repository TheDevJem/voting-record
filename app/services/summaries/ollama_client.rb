require "net/http"

module Summaries
  # Minimal client for a local Ollama server's chat API (https://github.com/ollama/ollama/blob/main/docs/api.md).
  class OllamaClient
    class Error < StandardError; end
    class Unavailable < Error; end

    def initialize(url: ENV.fetch("OLLAMA_URL", "http://localhost:11434"),
                   model: ENV.fetch("OLLAMA_MODEL", "qwen3:14b"))
      @uri = URI.join(url, "/api/chat")
      @model = model
    end

    attr_reader :model

    # Returns { content: String, stats: Hash }. `format` is a JSON schema the reply must follow.
    def chat(system:, user:, format: nil, num_ctx: 8192, temperature: 0.2)
      body = {
        model:, stream: false,
        think: false, # qwen3 "thinking" mode roughly doubles generation time on CPU; the schema gives enough structure
        keep_alive: "15m", # keep the model loaded between requests to avoid the ~20s reload
        format:,
        options: { num_ctx:, temperature: },
        messages: [ { role: "system", content: system }, { role: "user", content: user } ]
      }.compact

      response = Net::HTTP.start(@uri.host, @uri.port, open_timeout: 5, read_timeout: 1200) do |http|
        http.post(@uri.path, body.to_json, "Content-Type" => "application/json")
      end
      data = JSON.parse(response.body)
      raise Error, "Ollama #{response.code}: #{data['error']}" unless response.is_a?(Net::HTTPSuccess)

      { content: data.dig("message", "content").to_s, stats: stats(data) }
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, SocketError => e
      raise Unavailable, "Can't reach Ollama at #{@uri.host}:#{@uri.port} (#{e.class.name.demodulize}). Is `ollama serve` running?"
    rescue JSON::ParserError
      raise Error, "Ollama returned a non-JSON response (HTTP #{response&.code})"
    end

    private

    def stats(data)
      ns = 1e9
      {
        prompt_tokens: data["prompt_eval_count"], output_tokens: data["eval_count"],
        total_seconds: (data["total_duration"].to_f / ns).round(1),
        load_seconds: (data["load_duration"].to_f / ns).round(1),
        output_tokens_per_second: data["eval_duration"].to_i.positive? ? (data["eval_count"] / (data["eval_duration"] / ns)).round(1) : nil
      }
    end
  end
end

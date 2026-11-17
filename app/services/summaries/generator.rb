module Summaries
  # Packet -> local LLM -> validated summary hash.
  class Generator
    class InvalidOutput < StandardError; end

    def initialize(client: OllamaClient.new)
      @client = client
    end

    def call(member)
      packet = MemberPacket.new(member)
      result = @client.chat(system: Prompt::SYSTEM, user: Prompt.user_message(packet.to_h), format: Prompt::SCHEMA)
      { content: validate(result[:content], packet.to_h), stats: result[:stats], fingerprint: packet.fingerprint, model: @client.model,
        input: packet.to_h }
    end

    private

    # Structured output makes valid JSON very likely, but small models can still return empty fields.
    # key_issues may be empty, but only for a member whose record has no policy areas to write about.
    def validate(raw, packet)
      data = JSON.parse(raw)
      data["key_issues"] = Array(data["key_issues"]).select { |i| i.is_a?(Hash) && i["topic"].present? && i["summary"].present? }
      missing = Prompt::SCHEMA[:required].reject { |key| key == "key_issues" || data[key].present? }
      missing << "key_issues" if data["key_issues"].empty? && packet.dig(:legislation, :top_policy_areas).present?
      invalid!(raw, "Model response is missing: #{missing.join(', ')}") if missing.any?
      data
    rescue JSON::ParserError
      invalid!(raw, "Model response wasn't valid JSON")
    end

    # Keep the raw output in the log so prompt problems can be diagnosed.
    def invalid!(raw, message)
      Rails.logger.warn("[Summaries] #{message}. Raw model output:\n#{raw}")
      raise InvalidOutput, message
    end
  end
end

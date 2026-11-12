# Generates (or regenerates) a member's AI summary with the local Ollama model. Takes a few minutes on CPU.
class GenerateMemberSummaryJob < ApplicationJob
  queue_as :summaries
  # Ollama handles one generation at a time on this hardware; don't retry automatically. The UI offers Retry.
  discard_on ActiveRecord::RecordNotFound

  def perform(member_id)
    summary = MemberSummary.find_by!(member_id:)
    summary.update!(status: "running", error: nil)

    result = Summaries::Generator.new.call(summary.member)
    summary.update!(status: "complete", content: result[:content], stats: result[:stats], model: result[:model], input: result[:input],
                    fingerprint: MemberSummaries.fingerprint_for(result[:fingerprint]), generated_at: Time.current, error: nil)
  rescue Summaries::OllamaClient::Unavailable => e
    summary&.update!(status: "failed", error: e.message) # already user-facing: says to start Ollama
  rescue Summaries::Generator::InvalidOutput => e
    Rails.logger.warn("[Summaries] #{e.message} (member #{member_id})")
    summary&.update!(status: "failed",
                     error: "The AI model's answer was incomplete. Small local models vary from run to run, so trying again often works.")
  rescue Summaries::OllamaClient::Error => e
    Rails.logger.warn("[Summaries] #{e.message} (member #{member_id})")
    summary&.update!(status: "failed", error: "The local AI model returned an error. Check that the model in OLLAMA_MODEL is installed (`ollama list`).")
  rescue StandardError => e
    summary&.update!(status: "failed", error: "Unexpected error while generating the summary.")
    raise e
  end
end

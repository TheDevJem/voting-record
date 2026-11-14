# Decides when a member's summary needs (re)generating and kicks off the job.
module MemberSummaries
  module_function

  # "v<prompt version>:<data fingerprint>"
  def fingerprint_for(packet_fingerprint) = "v#{Summaries::Prompt::VERSION}:#{packet_fingerprint}"

  def current_fingerprint(member) = fingerprint_for(Summaries::MemberPacket.new(member).fingerprint)

  # Was this summary written with the current prompt?
  def current_prompt?(summary) = summary.fingerprint.to_s.start_with?("v#{Summaries::Prompt::VERSION}:")

  # Returns [summary, current_fingerprint], starting a generation job when:
  #   - the member has never had a summary,
  #   - `force` is set (the Regenerate / Retry buttons),
  #   - a previous job stalled, or
  #   - a finished summary was written with an older prompt version.
  # Data changes alone don't trigger a refresh: on a CPU-only machine each summary takes minutes, and a data
  # sync touches hundreds of members. Instead the API reports `stale` and the card offers Regenerate.
  # Never starts a second job while one is running. Failed summaries wait for an explicit Retry.
  def ensure(member, force: false)
    summary = member.summary || member.create_summary!(status: "pending")

    brand_new = summary.previously_new_record?
    busy = summary.in_progress? && !summary.stalled? && !brand_new
    wanted = brand_new || force || summary.stalled? || (summary.status == "complete" && !current_prompt?(summary))

    if wanted && !busy
      summary.update!(status: "pending", error: nil)
      GenerateMemberSummaryJob.perform_later(member.id)
    end
    # The fingerprint only feeds the `stale` flag, which is meaningless while a summary is being written.
    # Skipping it here keeps the frontend's 5-second status polls from rebuilding the whole packet each time.
    fingerprint = summary.in_progress? ? nil : current_fingerprint(member)
    [ summary, fingerprint ]
  end
end

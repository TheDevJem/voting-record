# Reads a member's summary and kicks off (re)generation when the user asks for it.
module MemberSummaries
  module_function

  # "v<prompt version>:<data fingerprint>"
  def fingerprint_for(packet_fingerprint) = "v#{Summaries::Prompt::VERSION}:#{packet_fingerprint}"

  def current_fingerprint(member) = fingerprint_for(Summaries::MemberPacket.new(member).fingerprint)

  # Returns [summary_or_nil, current_fingerprint] without starting any work. Opening a profile only reads:
  # on a CPU-only machine each summary takes minutes, so generation waits for an explicit Generate / Regenerate /
  # Retry click. A summary written with an older prompt or older data is reported as `stale` instead.
  def current(member)
    summary = member.summary
    [ summary, fingerprint_unless_busy(member, summary) ]
  end

  # Starts a generation job (the Generate / Regenerate / Retry buttons) unless one is already running.
  # A stalled job (e.g. the server restarted mid-generation) doesn't count as running.
  def generate(member)
    summary = member.summary || member.create_summary!(status: "pending")
    busy = summary.in_progress? && !summary.stalled? && !summary.previously_new_record?

    unless busy
      summary.update!(status: "pending", error: nil)
      GenerateMemberSummaryJob.perform_later(member.id)
    end
    [ summary, fingerprint_unless_busy(member, summary) ]
  end

  # The fingerprint only feeds the `stale` flag, which is meaningless while a summary is being written.
  # Skipping it keeps the frontend's status refetches from rebuilding the whole packet each time.
  def fingerprint_unless_busy(member, summary)
    summary.nil? || summary.in_progress? ? nil : current_fingerprint(member)
  end
end

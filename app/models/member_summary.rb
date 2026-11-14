class MemberSummary < ApplicationRecord
  STATUSES = %w[pending running complete failed].freeze
  # A job that hasn't finished in this long probably died (e.g. the server restarted mid-generation).
  STALLED_AFTER = 20.minutes

  belongs_to :member
  validates :status, inclusion: { in: STATUSES }

  # The job runs in the bin/jobs process; the cable adapter relays this to the web process and the browser.
  after_commit :broadcast_status, if: :saved_change_to_status?

  def in_progress? = status.in?(%w[pending running])
  def stalled? = in_progress? && updated_at < STALLED_AFTER.ago

  # Is the saved content out of date relative to the member's current data or the prompt?
  def stale?(current_fingerprint) = fingerprint != current_fingerprint

  private

  # Only a signal: the card refetches GET /summary, so the JSON shape lives in one place (the controller).
  def broadcast_status
    ActionCable.server.broadcast(MemberSummaryChannel.stream_for_member(member.bioguide_id), { status: })
  end
end

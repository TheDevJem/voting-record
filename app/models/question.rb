# A question typed into the "Ask about votes and bills" box, answered in the background by AnswerQuestionJob.
class Question < ApplicationRecord
  STATUSES = %w[pending running complete failed].freeze
  STAGES = %w[planning searching reading counting writing].freeze
  STALLED_AFTER = 20.minutes

  validates :text, presence: true, length: { maximum: 500 }
  validates :status, inclusion: { in: STATUSES }
  validates :stage, inclusion: { in: STAGES }, allow_nil: true

  before_validation { self.token ||= SecureRandom.urlsafe_base64(12) }
  after_commit :broadcast_status, if: -> { saved_change_to_status? || saved_change_to_stage? }

  def in_progress? = status.in?(%w[pending running])
  def stalled? = in_progress? && updated_at < STALLED_AFTER.ago

  def self.stream_for(token) = "question:#{token}"

  private

  # Only a signal; the page refetches GET /api/questions/:token so the JSON shape lives in the controller.
  def broadcast_status
    ActionCable.server.broadcast(self.class.stream_for(token), { status:, stage: })
  end
end

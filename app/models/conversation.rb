# A thread of questions in the "Ask" box. Each new question is answered with the earlier ones in view, so a
# follow-up like "what about Republicans?" or "which of those passed?" keeps the topic.
class Conversation < ApplicationRecord
  HISTORY = 3 # earlier answered questions given to the model; older ones rarely matter and cost prompt time

  has_many :questions, -> { order(:created_at, :id) }, dependent: :destroy, inverse_of: :conversation

  before_validation { self.token ||= SecureRandom.urlsafe_base64(12) }

  def self.stream_for(token) = "conversation:#{token}"

  def busy? = questions.any? { _1.in_progress? && !_1.stalled? }

  # The answered questions before `question`, oldest first, in the shape Ask::Pipeline takes.
  def history_before(question)
    questions.select { _1.status == "complete" && _1.created_at <= question.created_at && _1.id != question.id }
             .last(HISTORY).map { { question: _1.text, plan: _1.plan, answer: _1.answer } }
  end
end

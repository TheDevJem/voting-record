# Answers a question from the "Ask" box with the local model (Ask::Pipeline). About a minute on CPU.
# Shares the single-threaded `summaries` queue: the local model can only run one generation at a time anyway.
class AnswerQuestionJob < ApplicationJob
  queue_as :summaries
  discard_on ActiveRecord::RecordNotFound

  def perform(question_id)
    question = Question.find(question_id)
    question.update!(status: "running", stage: "planning", error: nil)

    pipeline = Ask::Pipeline.new
    output = pipeline.call(question.text) { |stage| question.update!(stage:) }
    question.update!(status: "complete", stage: nil, plan: output[:plan], result: output[:result], answer: output[:answer],
                     stats: output[:stats], model: pipeline.model)
  rescue Summaries::OllamaClient::Unavailable => e
    question&.update!(status: "failed", stage: nil, error: e.message)
  rescue Ask::Pipeline::InvalidOutput, Summaries::OllamaClient::Error => e
    Rails.logger.warn("[Ask] #{e.message} (question #{question_id})")
    question&.update!(status: "failed", stage: nil,
                      error: "The local AI model didn't return a usable answer. Small local models vary from run to run, so asking again often works.")
  rescue StandardError => e
    question&.update!(status: "failed", stage: nil, error: "Unexpected error while answering the question.")
    raise e
  end
end

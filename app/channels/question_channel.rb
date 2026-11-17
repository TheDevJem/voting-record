# Tells the question box when its question moves to a new stage or finishes, so the page refetches once per change.
class QuestionChannel < ApplicationCable::Channel
  def subscribed
    question = Question.find_by(token: params[:token].to_s)
    question ? stream_from(Question.stream_for(question.token)) : reject
  end
end

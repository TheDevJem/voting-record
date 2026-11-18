module Api
  # POST /api/questions        { q: "How many Democrats voted to fund Israel?", conversation: token? } -> 202,
  #                            answered in the background; without a conversation token a new conversation starts
  # GET  /api/questions/:token -> the question's status, stage, answer and the votes/bills it was based on
  class QuestionsController < ApplicationController
    wrap_parameters false # the body is just { q:, conversation: }; don't also nest it under "question"

    def create
      text = params.require(:q).to_s.squish
      return render_error(:bad_request, "missing_question", "Type a question first.") if text.blank?
      return render_error(:bad_request, "question_too_long", "Keep questions under 500 characters.") if text.length > 500
      unless SearchDocument.exists?
        return render_error(:service_unavailable, "search_not_indexed",
                            "The question box needs a search index. Run bin/rails search:index (see the README).")
      end

      conversation = params[:conversation].present? ? Conversation.find_by!(token: params[:conversation].to_s) : Conversation.new
      # A follow-up is planned from the answers before it, so it has to wait for the current one.
      if conversation.persisted? && conversation.busy?
        return render_error(:conflict, "question_in_progress", "Wait for the current answer before asking a follow-up.")
      end

      question = conversation.questions.build(text:)
      conversation.save!
      AnswerQuestionJob.perform_later(question.id)
      render status: :accepted, json: QuestionPayload.call(question)
    end

    def show
      render json: QuestionPayload.call(Question.includes(:conversation).find_by!(token: params[:id]))
    end
  end
end

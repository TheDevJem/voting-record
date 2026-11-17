module Api
  # POST /api/questions        { q: "How many Democrats voted to fund Israel?" } -> 202, answered in the background
  # GET  /api/questions/:token -> the question's status, stage, answer and the votes/bills it was based on
  class QuestionsController < ApplicationController
    wrap_parameters false # the body is just { q: }; don't also nest it under "question"

    def create
      text = params.require(:q).to_s.squish
      return render_error(:bad_request, "missing_question", "Type a question first.") if text.blank?
      return render_error(:bad_request, "question_too_long", "Keep questions under 500 characters.") if text.length > 500
      unless SearchDocument.exists?
        return render_error(:service_unavailable, "search_not_indexed",
                            "The question box needs a search index. Run bin/rails search:index (see the README).")
      end

      question = Question.create!(text:)
      AnswerQuestionJob.perform_later(question.id)
      render status: :accepted, json: payload(question)
    end

    def show
      render json: payload(Question.find_by!(token: params[:id]))
    end

    private

    def payload(q)
      stalled = q.stalled?
      {
        token: q.token, text: q.text, created_at: q.created_at,
        status: stalled ? "failed" : q.status, stage: stalled ? nil : q.stage,
        error: stalled ? "Answering stopped responding (the jobs process may have restarted). Ask again." : q.error,
        started_at: q.in_progress? ? q.created_at : nil,
        plan: q.plan&.slice("kind", "search", "keywords", "party_filter", "chamber_filter", "stance", "role_filter"),
        answer: q.answer, result: q.result, model: q.model, stats: q.stats
      }
    end
  end
end

module Api
  # The JSON for one question, shared by the questions and conversations endpoints.
  module QuestionPayload
    module_function

    PLAN_KEYS = %w[kind search keywords party_filter chamber_filter stance role_filter days].freeze

    def call(q)
      stalled = q.stalled?
      {
        token: q.token, conversation: q.conversation.token, text: q.text, created_at: q.created_at,
        status: stalled ? "failed" : q.status, stage: stalled ? nil : q.stage,
        error: stalled ? "Answering stopped responding (the jobs process may have restarted). Ask again." : q.error,
        started_at: q.in_progress? ? q.created_at : nil,
        plan: q.plan&.slice(*PLAN_KEYS),
        answer: q.answer, result: q.result, model: q.model, stats: q.stats
      }
    end
  end
end

module Api
  # GET /api/conversations/:token -> every question in the conversation, oldest first, as GET /api/questions/:token
  # returns them.
  class ConversationsController < ApplicationController
    def show
      conversation = Conversation.includes(:questions).find_by!(token: params[:id])
      render json: { token: conversation.token, busy: conversation.busy?,
                     questions: conversation.questions.map { QuestionPayload.call(_1) } }
    end
  end
end

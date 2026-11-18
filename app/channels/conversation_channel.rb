# Tells the question box when any question in its conversation moves to a new stage or finishes.
class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(token: params[:token].to_s)
    conversation ? stream_from(Conversation.stream_for(conversation.token)) : reject
  end
end

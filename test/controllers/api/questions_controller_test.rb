require "test_helper"

class Api::QuestionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    rc = RollCall.create!(chamber: "senate", congress: 119, session: 2, number: 1, question: "On Passage")
    SearchDocument.create!(record: rc, kind: "vote", content: "vote", content_digest: "x")
  end

  test "a question without a conversation starts one; a follow-up joins it once the first is answered" do
    post "/api/questions", params: { q: "How many Democrats support Israel?" }, as: :json
    assert_response :accepted
    first = response.parsed_body
    assert first["conversation"].present?
    assert_enqueued_jobs 1, only: AnswerQuestionJob

    post "/api/questions", params: { q: "What about Republicans?", conversation: first["conversation"] }, as: :json
    assert_response :conflict # the first is still pending

    Question.find_by!(token: first["token"]).update!(status: "complete", answer: "Some.")
    post "/api/questions", params: { q: "What about Republicans?", conversation: first["conversation"] }, as: :json
    assert_response :accepted

    get "/api/conversations/#{first['conversation']}"
    assert_response :success
    assert_equal [ "How many Democrats support Israel?", "What about Republicans?" ], response.parsed_body["questions"].map { _1["text"] }
  end

  test "the conversation's history passed to the pipeline is its earlier answered questions" do
    conversation = Conversation.create!
    done = conversation.questions.create!(text: "First?", status: "complete", answer: "A.", plan: { "kind" => "votes" })
    conversation.questions.create!(text: "Broken?", status: "failed")
    current = conversation.questions.create!(text: "Second?")
    assert_equal [ { question: "First?", plan: { "kind" => "votes" }, answer: "A." } ], conversation.reload.history_before(current)
    assert_empty conversation.history_before(done)
  end

  test "an unknown conversation is a 404" do
    post "/api/questions", params: { q: "Hi?", conversation: "nope" }, as: :json
    assert_response :not_found
  end
end

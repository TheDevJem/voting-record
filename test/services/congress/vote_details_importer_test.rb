require "test_helper"

class Congress::VoteDetailsImporterTest < ActiveSupport::TestCase
  # Canned Congress.gov responses by path.
  class FakeClient
    attr_reader :paths

    def initialize(responses) = (@responses, @paths = responses, [])

    def get(path, **)
      @paths << path
      @responses.fetch(path) { raise Congress::Http::NotFound, "404 #{path}" }
    end
  end

  setup do
    @amendment_vote = RollCall.create!(chamber: "house", congress: 119, session: 2, number: 243, question: "On Agreeing to the Amendment",
                                       legislation: "HR 8595")
    @bill = Bill.create!(congress: 119, bill_type: "HR", number: "8595", title: "Making appropriations for military construction")
  end

  def client(**extra)
    FakeClient.new({
      "/house-vote/119/2/243" => { "houseRollCallVote" => { "amendmentType" => "HAMDT", "amendmentNumber" => "235",
                                                            "amendmentAuthor" => "Greene of Georgia Part B Amendment No. 2" } },
      "/amendment/119/hamdt/235" => { "amendment" => { "purpose" => "An amendment to prohibit funds for Israel." } },
      "/bill/119/hr/8595/summaries" => { "summaries" => [
        { "actionDate" => "2026-05-01", "text" => "<p>Old summary.</p>" },
        { "actionDate" => "2026-05-15", "text" => "<p><strong>MilCon-VA Act</strong></p><p>This bill provides appropriations.</p>" } ] }
    }.merge(extra))
  end

  test "House amendment votes get the amendment's label, sponsor and purpose" do
    Congress::VoteDetailsImporter.new(client: client, log: ->(_) { }).call
    @amendment_vote.reload
    assert_equal "H.Amdt. 235", @amendment_vote.amendment_label
    assert_equal "Greene of Georgia", @amendment_vote.amendment_sponsor
    assert_equal "An amendment to prohibit funds for Israel.", @amendment_vote.amendment_purpose
  end

  test "voted bills get their latest CRS summary as plain text, once" do
    fake = client
    importer = Congress::VoteDetailsImporter.new(client: fake, log: ->(_) { })
    importer.call
    assert_equal "MilCon-VA Act This bill provides appropriations.", @bill.reload.summary
    importer.call # already looked up: no further requests
    assert_equal 1, fake.paths.count("/bill/119/hr/8595/summaries")
    assert_equal 1, fake.paths.count("/house-vote/119/2/243")
  end
end

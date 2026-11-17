require "test_helper"

class Ask::PipelineTest < ActiveSupport::TestCase
  # Stands in for Ollama: answers each step from a script, keyed by which system prompt it was given.
  class FakeClient
    attr_reader :calls

    def initialize(replies) = (@replies, @calls = replies, [])
    def model = "fake-model"

    def chat(system:, user:, format:)
      step = { Ask::Prompts::PLAN_SYSTEM => :plan, Ask::Prompts::READ_VOTES_SYSTEM => :read_votes,
               Ask::Prompts::READ_BILLS_SYSTEM => :read_bills, Ask::Prompts::WRITE_SYSTEM => :write }.fetch(system)
      @calls << [ step, user ]
      { content: @replies.fetch(step).to_json, stats: { total_seconds: 1.0 } }
    end
  end

  # Returns the documents in a fixed order, so the test controls what "search" found.
  class FakeRetriever
    attr_reader :args

    def initialize(docs) = @docs = docs
    def call(query, **opts) = (@args = [ query, opts ]) && @docs
  end

  setup do
    @dem = Member.create!(bioguide_id: "D000001", chamber: "senate", full_name: "Dana Dem", party: "Democratic", state: "Ohio", state_code: "OH")
    @dem2 = Member.create!(bioguide_id: "D000002", chamber: "senate", full_name: "Drew Dem", party: "Democratic", state: "Iowa", state_code: "IA")
    @rep = Member.create!(bioguide_id: "R000001", chamber: "senate", full_name: "Riley Rep", party: "Republican", state: "Utah", state_code: "UT")
    @sale = RollCall.create!(chamber: "senate", congress: 119, session: 2, number: 81, question: "On the Motion to Discharge",
                             legislation: "S.J.Res. 138", result: "Motion to Discharge Rejected", voted_at: Time.zone.parse("2026-04-15"))
    @other = RollCall.create!(chamber: "senate", congress: 119, session: 2, number: 90, question: "On the Nomination",
                              legislation: "PN 1", description: "Jo Smith, to be Secretary", voted_at: Time.zone.parse("2026-04-20"))
    # Yea on discharging a disapproval resolution = against the sale.
    { @dem => "Yea", @dem2 => "Nay", @rep => "Nay" }.each { |m, pos| VotePosition.create!(roll_call: @sale, member: m, position: pos) }
    @docs = [ @sale, @other ].map do |rc|
      SearchDocument.create!(record: rc, kind: "vote", chamber: "senate", content: "vote #{rc.number}", content_digest: rc.number.to_s)
    end
  end

  def replies(**overrides)
    { plan: { kind: "votes", search: "military aid to Israel", keywords: [ "Israel" ], party: "Democratic", chamber: "any",
              stance: "supported funding for Israel", role: "either" },
      read_votes: { votes: [ { ref: "V1", relevant: true, yea_supports_stance: "no", reason: "Disapproval of an arms sale; Nay keeps the sale." },
                             { ref: "V2", relevant: false, yea_supports_stance: "unclear", reason: "An unrelated nomination." } ] },
      write: { answer: "One Democrat voted to keep the sale." } }.merge(overrides)
  end

  test "counts come from the votes, using the direction the model chose, filtered to the party asked about" do
    client = FakeClient.new(replies)
    stages = []
    out = Ask::Pipeline.new(client:, retriever: FakeRetriever.new(@docs)).call("How many Democrats voted to fund Israel?") { stages << _1 }

    assert_equal %w[planning searching reading counting writing], stages
    vote = out[:result][:votes].sole
    assert_equal "Nay", vote[:counts_as]
    assert_equal 1, vote[:matching] # only Drew Dem: Riley Rep also voted Nay but isn't a Democrat
    assert_equal %w[D000002 D000001], vote[:members].map { _1[:bioguide_id] } # by party, then state (IA before OH)
    assert_equal({ "Democratic" => { "Yea" => 1, "Nay" => 1 }, "Republican" => { "Nay" => 1 } }, vote[:breakdown])
    assert_equal [ [ "vote", "vote 90" ] ], out[:result][:rejected].map { [ _1[:kind], _1[:text] ] }
    assert_nil out[:result][:bills] # a votes-only question doesn't search bills
    assert_equal "One Democrat voted to keep the sale.", out[:answer]
    assert_match '"members_matching_stance_in_party_asked": 1', client.calls.last.last # the writer sees the SQL count
    assert_match '"distinct_members_matching_by_votes": 1', client.calls.last.last
    assert_match "What a Yea means: A Yea vote moves the measure out of committee", client.calls[1].last
  end

  test "an invalid party or chamber from the model is ignored rather than filtering everything out" do
    plan = replies[:plan].merge(party: "Whig", chamber: "moon")
    retriever = FakeRetriever.new(@docs)
    out = Ask::Pipeline.new(client: FakeClient.new(replies(plan:)), retriever:).call("q")
    assert_nil out[:plan]["party_filter"]
    assert_nil retriever.args.last[:chamber]
    assert_equal 3, out[:result][:votes].sole[:members].size
  end

  test "without a stance no direction is assigned, even if the model gives one" do
    plan = replies[:plan].merge(stance: "")
    vote = Ask::Pipeline.new(client: FakeClient.new(replies(plan:)), retriever: FakeRetriever.new(@docs)).call("q")[:result][:votes].sole
    assert_nil vote[:counts_as]
    assert_nil vote[:matching]
  end

  test "bill questions list the sponsors of the bills judged relevant" do
    bill = Bill.create!(congress: 119, bill_type: "S", number: "12", title: "Social Security Expansion Act", policy_area: "Social Welfare")
    BillSponsorship.create!(bill:, member: @dem, role: "sponsor")
    BillSponsorship.create!(bill:, member: @rep, role: "cosponsor")
    doc = SearchDocument.create!(record: bill, kind: "bill", content: "S. 12", content_digest: "b")
    plan = replies[:plan].merge(kind: "bills", party: "any", stance: "", role: "either")
    read_bills = { bills: [ { ref: "B1", relevant: true, reason: "About Social Security." } ] }
    out = Ask::Pipeline.new(client: FakeClient.new(replies(plan:, read_bills:)), retriever: FakeRetriever.new([ doc ])).call("q")

    item = out[:result][:bills].sole
    assert_equal [ %w[D000001 sponsor], %w[R000001 cosponsor] ], item[:members].map { [ _1[:bioguide_id], _1[:role] ] }
    assert_equal 2, out[:result][:bill_member_count]
    assert_nil out[:result][:votes] # a bills-only question doesn't search votes
  end

  test "a sentence claiming member names aren't available is dropped from the answer" do
    write = { answer: "Seven Democrats voted Nay on S.J.Res. 32. The app does not provide a list of individual member names." }
    out = Ask::Pipeline.new(client: FakeClient.new(replies(write:)), retriever: FakeRetriever.new(@docs)).call("q")
    assert_equal "Seven Democrats voted Nay on S.J.Res. 32.", out[:answer]
  end

  test "a general support question uses votes and bills, with distinct members counted across both" do
    pro = Bill.create!(congress: 119, bill_type: "S", number: "20", title: "United States-Israel Defense Partnership Act")
    con = Bill.create!(congress: 119, bill_type: "S", number: "21", title: "Block the Bombs Act")
    BillSponsorship.create!(bill: pro, member: @dem, role: "sponsor")   # also voted Yea (against the sale) below
    BillSponsorship.create!(bill: con, member: @dem2, role: "cosponsor") # voted Nay (for the sale)
    bill_docs = [ pro, con ].map { SearchDocument.create!(record: _1, kind: "bill", content: _1.title, content_digest: _1.number) }
    retriever = Class.new do
      define_method(:initialize) { |votes, bills| @by_kind = { "vote" => votes, "bill" => bills } }
      define_method(:call) { |_query, kind:, **| @by_kind.fetch(kind) }
    end.new(@docs, bill_docs)
    read_bills = { bills: [ { ref: "B1", relevant: true, sponsoring_supports_stance: "yes", reason: "Supports Israel's defense." },
                            { ref: "B2", relevant: true, sponsoring_supports_stance: "no", reason: "Would restrict arms to Israel." } ] }
    plan = replies[:plan].merge(kind: "both", stance: "support Israel")
    client = FakeClient.new(replies(plan:, read_bills:))
    out = Ask::Pipeline.new(client:, retriever:).call("How many Democrats support Israel?")

    assert_equal %i[plan read_votes read_bills write], client.calls.map(&:first)
    assert_equal [ true, false ], out[:result][:bills].map { _1[:supports] }
    facts = JSON.parse(client.calls.last.last[/Facts:\n(.*)/m, 1])
    # Dana: sponsored the pro bill but voted against the sale; Drew: voted for the sale but cosponsored the con bill.
    assert_equal 2, facts["distinct_members_matching_stance"]
    assert_equal 1, facts["distinct_members_matching_by_votes"]
    assert_equal 1, facts["distinct_members_matching_by_bills"]
    assert_equal 2, facts["distinct_members_on_both_sides"]
  end
end

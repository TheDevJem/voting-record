require "test_helper"

class Ask::VoteMeaningTest < ActiveSupport::TestCase
  def meaning(question, title)
    Ask::VoteMeaning.for(RollCall.new(question:, description: title), nil)
  end

  test "a discharge motion on a disapproval resolution means blocking the action" do
    text = meaning("On the Motion to Discharge",
                   "A joint resolution providing for congressional disapproval of the proposed foreign military sale to the Government of Israel")
    assert_match "moves the measure out of committee toward a vote, i.e. supports it", text
    assert_match "BLOCK the proposed foreign military sale to the Government of Israel", text
  end

  test "ordinary passage supports the measure as titled" do
    assert_match "A Yea vote supports the measure; a Nay vote opposes it. The measure would do this: Major Richard Star Act",
                 meaning("On Passage", "Major Richard Star Act")
  end

  test "a vote with no title says so instead of trailing off" do
    assert_match "not described in this data", meaning("On Passage", nil)
  end

  test "House amendment votes are described by the amendment's purpose, not the bill" do
    rc = RollCall.new(question: "On Agreeing to the Amendment", amendment_purpose: "Amendment sought to cut the Pentagon's civilian workforce.")
    assert_equal "A Yea vote supports adopting the amendment: Amendment sought to cut the Pentagon's civilian workforce.",
                 Ask::VoteMeaning.for(rc, Bill.new(title: "National Defense Authorization Act for Fiscal Year 2027"))
  end

  test "tabling and recommitting are opposition to the measure" do
    assert_match "sets aside (kills)", meaning("On the Motion to Table", "An amendment to cut foreign aid")
    assert_match "sends the bill back to committee", meaning("On Motion to Recommit", "Pregnant Students' Rights Act")
  end
end

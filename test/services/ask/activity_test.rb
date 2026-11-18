require "test_helper"

class Ask::ActivityTest < ActiveSupport::TestCase
  setup do
    @today = Date.new(2026, 11, 18)
    members = { "D1" => "Democratic", "D2" => "Democratic", "D3" => "Democratic", "R1" => "Republican", "R2" => "Republican" }
    @members = members.to_h { |id, party| [ id, Member.create!(bioguide_id: id, chamber: "senate", full_name: "Member #{id}", party:, state: "Ohio", state_code: "OH") ] }
  end

  def roll_call(number, date, legislation:, question:, positions:, description: nil)
    rc = RollCall.create!(chamber: "senate", congress: 119, session: 2, number:, question:, legislation:, description:,
                          result: "Agreed to", voted_at: Time.zone.parse(date.to_s))
    positions.each { |id, pos| VotePosition.create!(roll_call: rc, member: @members.fetch(id), position: pos) }
    rc
  end

  test "votes in the window are grouped by measure, with each party's lean and the members who broke from it" do
    nominee = "Jo Smith, of Ohio, to be Judge"
    roll_call(1, @today - 3, legislation: "PN 5", question: "On the Cloture Motion", description: nominee,
              positions: { "D1" => "Nay", "D2" => "Nay", "D3" => "Yea", "R1" => "Yea", "R2" => "Yea" })
    roll_call(2, @today - 1, legislation: "PN 5", question: "On the Nomination", description: nominee,
              positions: { "D1" => "Nay", "D2" => "Nay", "D3" => "Nay", "R1" => "Yea", "R2" => "Yea" })
    roll_call(3, @today - 30, legislation: "PN 9", question: "On the Nomination", description: "Old nominee", positions: {})

    votes = Ask::Activity.call(days: 7, today: @today)[:votes]
    assert_equal 2, votes[:total_roll_calls]
    group = votes[:items].sole
    assert_equal [ "PN 5", nominee ], group.values_at(:legislation, :title)
    cloture, confirm = group[:votes]
    assert_equal [ "D3" ], cloture[:members_who_broke_with_party].map { _1[:bioguide_id] }
    assert_equal "party-line: Democrats mostly Nay, Republicans mostly Yea", confirm[:pattern]
    assert_equal({ "Democratic" => { "Nay" => 3 }, "Republican" => { "Yea" => 2 } }, confirm[:breakdown])

    only_reps = Ask::Activity.call(days: 7, party: "Republican", today: @today)[:votes][:items].sole[:votes].first
    assert_empty only_reps[:members_who_broke_with_party] # D3's break isn't listed when asking about Republicans
  end

  test "new bills are counted by sponsor party and ranked by cosponsors; older bills count only when they moved forward" do
    fresh = Bill.create!(congress: 119, bill_type: "HR", number: "1", title: "Fresh Act", policy_area: "Health", introduced_date: @today - 2)
    popular = Bill.create!(congress: 119, bill_type: "S", number: "2", title: "Popular Act", policy_area: "Health", introduced_date: @today - 4)
    passed = Bill.create!(congress: 119, bill_type: "S", number: "3", title: "Passed Act", introduced_date: @today - 200,
                          latest_action_date: @today - 1, latest_action_text: "Passed Senate without amendment by Unanimous Consent.")
    referred = Bill.create!(congress: 119, bill_type: "S", number: "4", title: "Referred Act", introduced_date: @today - 200,
                            latest_action_date: @today - 1, latest_action_text: "Read twice and referred to the Committee on Finance.")
    BillSponsorship.create!(bill: fresh, member: @members["R1"], role: "sponsor")
    BillSponsorship.create!(bill: popular, member: @members["D1"], role: "sponsor")
    %w[D2 R2].each { BillSponsorship.create!(bill: popular, member: @members[_1], role: "cosponsor") }
    [ passed, referred ].each { BillSponsorship.create!(bill: _1, member: @members["D2"], role: "sponsor") }

    activity = Ask::Activity.call(days: 7, today: @today)
    introduced = activity[:introduced]
    assert_equal 2, introduced[:total]
    assert_equal({ "Republican" => 1, "Democratic" => 1 }, introduced[:by_sponsor_party])
    assert_equal({ "Health" => 2 }, introduced[:top_policy_areas])
    assert_equal [ "S. 2", "H.R. 1" ], introduced[:most_cosponsored].map { _1[:label] }
    assert_equal({ "Democratic" => 1, "Republican" => 1 }, introduced[:most_cosponsored].first[:cosponsor_parties])

    advanced = activity[:advanced]
    assert_equal [ [ "S. 3", "passed a chamber" ] ], advanced[:items].map { _1.values_at(:label, :step) }

    assert_equal [ "H.R. 1" ], Ask::Activity.call(days: 7, chamber: "house", today: @today)[:introduced][:most_cosponsored].map { _1[:label] }
    facts = Ask::Activity.facts(activity)
    assert_match "S. 2 (#{@today - 4}), sponsor Member D1 (D-OH), 2 cosponsors (1 Democratic, 1 Republican): Popular Act",
                 facts[:bills_introduced][:most_cosponsored].first
  end
end

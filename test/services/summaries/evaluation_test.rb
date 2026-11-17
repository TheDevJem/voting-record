require "test_helper"

class Summaries::EvaluationTest < ActiveSupport::TestCase
  INPUT = {
    member: { name: "Pat Example", party: "Democratic", seat: "Senator from Ohio" },
    committees: [ "Senate Committee on Finance" ],
    legislation: {
      sponsored_count: 3, cosponsored_count: 1,
      top_policy_areas: [ "Health (2 bills)", "Taxation (1 bills)" ],
      recent_sponsored: [ "S. 12 — Rural Clinics Act — [Health]", "S. 40 — Drug Pricing Act — [Health]",
                          "S. 77 — Small Business Tax Relief Act — [Taxation]" ],
      recent_cosponsored: [ "S.Res. 5 — A resolution honoring nurses — [Health]",
                            "S. 88 — A bill to amend title 38, and for other purposes." ]
    },
    voting: {
      roll_calls_in_data: 100, agreed_with_party_majority_percent: 91, party_agreement_vote_count: 90,
      votes_against_party_majority: [ "2026-03-02: On the Nomination — PN 1129 — Jo Smith, to be Secretary → voted Yea (Democratic majority voted Nay); result: Nomination Confirmed" ],
      recent_final_votes: []
    },
    data_scope: "Bills from the 119th Congress only; votes are the 100 most recent Senate roll calls synced into this app."
  }.freeze

  GOOD = {
    overview: "Pat Example is a Democratic Senator from Ohio. Most of their bills concern health and taxation.",
    key_issues: [
      { topic: "Health", summary: "They sponsored bills on rural clinics and drug prices.",
        evidence: [ "S. 12 — Rural Clinics Act — [Health]", "S. 40" ] },
      { topic: "Taxation", summary: "They sponsored small business tax relief.",
        evidence: [ "S. 77 — Small Business Tax Relief Act — [Taxation]" ] }
    ],
    voting_pattern: "They agreed with the Democratic majority on 91% of votes. They broke with it on 2026-03-02: On the Nomination (PN 1129).",
    limitations: "Covers bills from the 119th Congress and the 100 most recent Senate roll calls only."
  }.freeze

  def evaluate(**changes) = Summaries::Evaluation.new(GOOD.merge(changes), INPUT)
  def check(evaluation, name) = evaluation.results.find { |r| r.name == name }

  test "a faithful summary passes every check" do
    evaluation = evaluate
    assert_equal [], evaluation.failures.map { |f| "#{f.name}: #{f.detail}" }
    assert_equal 1.0, evaluation.score
  end

  test "evidence that names a bill not in the record fails, reworded real evidence passes" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "Sponsored S. 12 on clinics", "S. 999 — Made Up Act — [Health]" ]),
               GOOD[:key_issues][1] ]
    result = check(evaluate(key_issues: issues), :evidence_grounded)
    refute result.passed
    assert_match "1 reworded, 1 not in record", result.detail
    assert_match "S. 999", result.detail
  end

  test "bill numbers in prose must exist in the record" do
    result = check(evaluate(overview: "Pat Example is a Democratic Senator from Ohio. They wrote H.R. 4 and S.Res. 5."), :cited_ids_exist)
    refute result.passed
    assert_equal "not in record: H.R.4", result.detail
  end

  test "S.Res. is not mistaken for S." do
    result = check(evaluate(overview: "Pat Example is a Democratic Senator from Ohio. They cosponsored S.Res. 5."), :cited_ids_exist)
    assert result.passed, result.detail
  end

  test "party agreement must be the record's percentage and nothing else" do
    refute check(evaluate(voting_pattern: "They agreed with their party 90 percent of the time."), :party_agreement).passed
    refute check(evaluate(voting_pattern: "They agreed 91% of the time and missed 5% of votes."), :party_agreement).passed
    refute check(evaluate(voting_pattern: "They usually vote with their party."), :party_agreement).passed
  end

  test "loaded labels fail unless the record itself uses the word" do
    refute check(evaluate(overview: "Pat Example is a progressive Senator from Ohio. They are pro-labor."), :neutral_language).passed
    input = INPUT.deep_merge(legislation: { recent_sponsored: [ "S. 12 — Progressive Care Act — [Health]" ] })
    content = GOOD.merge(overview: "Pat Example is a Democratic Senator from Ohio. They sponsored the Progressive Care Act.")
    assert check(Summaries::Evaluation.new(content, input), :neutral_language).passed
  end

  test "claims about length of service fail" do
    [ "serving since 2025", "first elected in 2018", "for over 10 years", "a two-term senator",
      "whose current term began in 2025", "elected in 2018", "who took office in 2021" ].each do |claim|
      result = check(evaluate(overview: "Pat Example is a Democratic Senator from Ohio, #{claim}. Most bills concern health."), :no_tenure_claim)
      refute result.passed, "expected #{claim.inspect} to fail"
    end
  end

  test "topics must come from top policy areas and evidence tags must match the topic" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "S. 77 — Small Business Tax Relief Act — [Taxation]" ]),
               GOOD[:key_issues][1].merge(topic: "Small Business") ]
    evaluation = evaluate(key_issues: issues)
    assert_equal "not a top policy area: Small Business", check(evaluation, :topics_from_policy_areas).detail
    assert_match 'Taxation evidence under "Health"', check(evaluation, :evidence_on_topic).detail
  end

  test "limitations must repeat the numbers in data_scope" do
    result = check(evaluate(limitations: "Covers recent bills and votes only."), :limitations_match_scope)
    refute result.passed
    assert_equal "doesn't mention 119, 100", result.detail
  end

  test "format checks counts, sentence lengths and markdown" do
    result = check(evaluate(overview: "Pat Example is a **Democratic** Senator from Ohio.",
                            key_issues: [ GOOD[:key_issues][0] ]), :format)
    refute result.passed
    assert_match "1 key issues", result.detail
    assert_match "overview has 1 sentences", result.detail
    assert_match "markdown", result.detail
  end

  test "abbreviations don't count as sentence ends" do
    overview = "Pat Example is a U.S. Senator from Ohio who serves with Keith R. Sonderling. They sponsored S. 12 and H.R. 4."
    assert check(evaluate(overview:), :format).passed
  end

  test "a real bill number with a title the record doesn't give it fails" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "S. 12 — Made Up Title Act — [Health]" ]), GOOD[:key_issues][1] ]
    result = check(evaluate(key_issues: issues), :evidence_grounded)
    refute result.passed
    assert_match "1 with the wrong title", result.detail
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "S. 12 — Rural Clinics Act" ]), GOOD[:key_issues][1] ]
    assert check(evaluate(key_issues: issues), :evidence_grounded).passed
  end

  test "votes in voting_pattern must come from votes_against_party_majority with the recorded position" do
    assert check(evaluate(voting_pattern: "They agreed 91% of the time. They voted Yea on PN 1129 while the Democratic majority voted Nay."),
                 :party_breaks_from_record).passed
    result = check(evaluate(voting_pattern: "They agreed 91% of the time. They voted Nay on PN 1129."), :party_breaks_from_record)
    refute result.passed
    assert_match "says Nay on PN1129, record says Yea", result.detail
    result = check(evaluate(voting_pattern: "They agreed 91% of the time. They broke with the party on S. 77."), :party_breaks_from_record)
    assert_match "not in votes_against_party_majority: S.77", result.detail
  end

  test "the party-agreement percentage must use the record's denominator" do
    result = check(evaluate(voting_pattern: "They agreed with the Democratic majority on 91 percent of the 100 roll calls in the data."), :party_agreement)
    refute result.passed
    assert_match "out of 90 votes, summary says out of 100", result.detail
    assert check(evaluate(voting_pattern: "They agreed with the Democratic majority on 91% of 90 votes. They missed 3 votes."), :party_agreement).passed
  end

  test "untagged bill evidence is checked against the record's tag for that bill" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "S. 77", "S. 88 — A bill to amend title 38, and for other purposes." ]),
               GOOD[:key_issues][1] ]
    detail = check(evaluate(key_issues: issues), :evidence_on_topic).detail
    assert_match 'Taxation evidence under "Health"', detail
    assert_match 'S.88 (no policy area in the record) under "Health"', detail
  end

  test "a record with no policy areas wants no key issues instead of placeholders" do
    input = INPUT.deep_merge(legislation: { top_policy_areas: [], recent_sponsored: [], recent_cosponsored: [] })
    empty = Summaries::Evaluation.new(GOOD.merge(key_issues: []), input)
    %i[evidence_grounded topics_from_policy_areas format].each { |name| assert check(empty, name).passed, check(empty, name).detail }

    filler = [ { topic: "No Data Available", summary: "No bills.", evidence: [ "sponsored_count: 0" ] } ] * 2
    padded = Summaries::Evaluation.new(GOOD.merge(key_issues: filler), input)
    refute check(padded, :topics_from_policy_areas).passed
    assert_match "duplicate topics", check(padded, :format).detail
  end

  test "more than 3 evidence items for a topic fails format" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "S. 12", "S. 40", "S.Res. 5", "S. 12" ]), GOOD[:key_issues][1] ]
    assert_match "4 evidence items", check(evaluate(key_issues: issues), :format).detail
  end

  test "House votes' compact bill codes are recognized and checked" do
    input = INPUT.deep_merge(voting: { votes_against_party_majority: [
      "2026-11-12: On Agreeing to the Resolution — HRES 1247 — Yea-and-Nay → voted Yea (Democratic majority voted Nay); result: Passed" ] })
    wrong = Summaries::Evaluation.new(GOOD.merge(voting_pattern: "They agreed 91% of the time. They voted Nay on HRES 1247."), input)
    assert_match "says Nay on H.Res.1247, record says Yea", check(wrong, :party_breaks_from_record).detail
    right = Summaries::Evaluation.new(GOOD.merge(voting_pattern: "They agreed 91% of the time. They voted Yea on H.Res. 1247."), input)
    assert check(right, :party_breaks_from_record).passed, check(right, :party_breaks_from_record).detail
    assert check(right, :cited_ids_exist).passed
  end

  test "policy areas must match exactly, so Law is not Crime and Law Enforcement" do
    input = INPUT.deep_merge(legislation: {
      top_policy_areas: [ "Crime and Law Enforcement (2 bills)", "Health (2 bills)" ],
      recent_sponsored: [ "H.R. 9 — Police Standards Act — [Crime and Law Enforcement]", "H.Res. 4 — Impeaching a judge — [Law]",
                          "S. 12 — Rural Clinics Act — [Health]" ] })
    issues = [ { topic: "Crime and Law Enforcement", summary: "Bills on policing.",
                 evidence: [ "H.R. 9 — Police Standards Act — [Crime and Law Enforcement]", "H.Res. 4 — Impeaching a judge — [Law]" ] },
               { topic: "Health", summary: "A clinics bill.", evidence: [ "S. 12 — Rural Clinics Act — [Health]" ] } ]
    result = check(Summaries::Evaluation.new(GOOD.merge(key_issues: issues), input), :evidence_on_topic)
    assert_equal 'Law evidence under "Crime and Law Enforcement"', result.detail
  end

  test "a policy-area count or other copied text without a bill or vote is not evidence" do
    issues = [ GOOD[:key_issues][0].merge(evidence: [ "Health (2 bills)", "Senate Committee on Finance" ]), GOOD[:key_issues][1] ]
    result = check(evaluate(key_issues: issues), :evidence_grounded)
    refute result.passed
    assert_match "2 not a bill or vote", result.detail
  end

  test "topics must be top policy areas that have tagged recent bills" do
    input = INPUT.deep_merge(legislation: { top_policy_areas: [ "Education (9 bills)", "Health (2 bills)", "Taxation (1 bills)" ] })
    issues = GOOD[:key_issues] + [ { topic: "Education", summary: "Many education bills.", evidence: [ "S. 12" ] } ]
    result = check(Summaries::Evaluation.new(GOOD.merge(key_issues: issues), input), :topics_from_policy_areas)
    assert_equal "no recent bills tagged: Education", result.detail
  end
end

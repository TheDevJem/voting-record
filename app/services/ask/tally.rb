module Ask
  # The counting half of a question, done in SQL so every number is exact. Takes the votes or bills the model
  # judged relevant and returns per-item breakdowns plus member lists for the page and the answer writer.
  module Tally
    module_function

    POSITIONS = %w[Yea Nay Present Not\ Voting].freeze

    # votes: [{ roll_call:, bill:, counts_as: "Yea"/"Nay"/nil, reason: }]
    def votes(votes, party:)
      votes.map do |v|
        rc = v[:roll_call]
        positions = VotePosition.where(roll_call_id: rc.id).joins(:member)
                                .pluck("members.bioguide_id", "members.full_name", "members.party", "members.state_code",
                                       "members.district", :position)
        breakdown = positions.group_by { _1[2] }.sort.to_h.transform_values { |rows| rows.map(&:last).tally.slice(*POSITIONS) }
        members = positions.select { |p| party.nil? || p[2] == party }.sort_by { |p| [ p[2], p[3], p[1] ] }.map do |id, name, pty, st, dist, pos|
          { bioguide_id: id, name:, party: pty, state_code: st, district: dist, position: pos }
        end
        matching = v[:counts_as] ? members.count { _1[:position] == v[:counts_as] } : nil

        { roll_call_id: rc.id, chamber: rc.chamber, number: rc.number, date: rc.voted_at&.to_date, question: rc.question,
          legislation: rc.legislation_label, title: v[:bill]&.title || rc.topical_description, policy_area: v[:bill]&.policy_area,
          result: rc.result, yeas: rc.yeas, nays: rc.nays, source_url: rc.source_url, bill_url: v[:bill]&.congress_gov_url,
          amendment: rc.amendment_purpose && { label: rc.amendment_label, sponsor: rc.amendment_sponsor, purpose: rc.amendment_purpose },
          summary: v[:bill]&.summary&.truncate(600),
          meaning: v[:meaning], counts_as: v[:counts_as], reason: v[:reason], breakdown:, matching:, members: }
      end
    end

    # bills: [{ bill:, reason:, supports: true/false/nil }]; role: "sponsor", "cosponsor" or nil for either.
    def bills(bills, party:, role:)
      scope = BillSponsorship.where(bill_id: bills.map { _1[:bill].id }).joins(:member)
      scope = scope.where(role:) if role
      scope = scope.where(members: { party: }) if party
      rows = scope.pluck(:bill_id, :role, "members.bioguide_id", "members.full_name", "members.party", "members.state_code",
                         "members.chamber", "members.district")
      by_bill = rows.group_by(&:first)

      items = bills.map do |b|
        bill = b[:bill]
        sponsors = Array(by_bill[bill.id]).sort_by { |r| [ r[1] == "sponsor" ? 0 : 1, r[4], r[3] ] }.map do |_, rl, id, name, pty, st, ch, dist|
          { bioguide_id: id, name:, party: pty, state_code: st, chamber: ch, district: dist, role: rl }
        end
        { bill_id: bill.id, label: bill.label, title: bill.title, policy_area: bill.policy_area, introduced_date: bill.introduced_date,
          latest_action_text: bill.latest_action_text, url: bill.congress_gov_url, reason: b[:reason], supports: b[:supports],
          summary: bill.summary&.truncate(600),
          party_counts: sponsors.map { _1[:party] }.tally, members: sponsors }
      end
      { items:, member_count: rows.map { _1[2] }.uniq.size }
    end
  end
end

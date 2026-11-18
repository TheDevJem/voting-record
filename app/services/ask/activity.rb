module Ask
  # "What happened in Congress lately?": everything in a recent window, gathered and counted in SQL. No search and
  # no judging: the model only writes up the highlights from what this returns.
  #
  #   votes        - roll calls in the window, grouped by the measure they were on (a nomination's cloture and
  #                  confirmation votes together), each with party breakdowns and the members who broke with
  #                  their party
  #   introduced   - bills introduced in the window: totals by party and policy area, the most-cosponsored ones,
  #                  and the members who introduced the most
  #   advanced     - older bills whose latest action in the window was a step forward (passed, reported, sent to
  #                  the President, became law), not just a referral to committee
  module Activity
    module_function

    MAX_VOTE_GROUPS = 15
    MAX_NOTABLE_BILLS = 10
    MAX_ADVANCED_BILLS = 12
    MAX_BREAKERS_LISTED = 8
    MAJOR_PARTIES = %w[Democratic Republican].freeze

    # Ordered by how far along it got: law first, then sent to the President, passed, reported, put on a calendar.
    ADVANCING = [
      [ "became law", /became public law|signed by (?:the )?president/i ],
      [ "vetoed", /vetoed/i ],
      [ "sent to the President", /presented to (?:the )?president/i ],
      # The rest follow a chamber passing it: the other chamber receiving it, the motion to reconsider being tabled.
      [ "passed a chamber", /\bpassed\b|agreed to (?:in|by) (?:the )?(?:house|senate)|considered,? and agreed to|resolving differences|
                              received in the (?:house|senate)|message on (?:house|senate) action|held at the desk|
                              motion to reconsider laid on the table/xi ],
      [ "reported by committee", /\breported\b|ordered to be reported/i ],
      [ "placed on a calendar", /placed on (?:the )?.*calendar/i ]
    ].freeze

    def call(days:, chamber: nil, party: nil, today: Date.current)
      from = today - days
      { window: { days:, from:, to: today, chamber:, party: },
        data_through: { latest_vote: RollCall.maximum(:voted_at)&.to_date, latest_bill_action: Bill.maximum(:latest_action_date) },
        votes: votes(from, chamber, party),
        introduced: introduced(from, chamber, party),
        advanced: advanced(from, chamber, party) }
    end

    def votes(from, chamber, party)
      scope = RollCall.where(voted_at: from.beginning_of_day..).order(:voted_at, :number)
      scope = scope.where(chamber:) if chamber
      roll_calls = scope.to_a
      bills = RollCall.bills_for(roll_calls)
      positions = VotePosition.where(roll_call_id: roll_calls.map(&:id)).joins(:member)
                              .pluck(:roll_call_id, :position, "members.bioguide_id", "members.full_name", "members.party",
                                     "members.state_code", "members.district").group_by(&:first)

      groups = roll_calls.group_by { |rc| [ rc.chamber, rc.legislation_label, rc.amendment_purpose || title_for(rc, bills) ] }
      items = groups.map do |(ch, legislation, _), rcs|
        bill = bills[rcs.first.bill_key]
        { chamber: ch, legislation:, title: title_for(rcs.first, bills), amendment: rcs.first.amendment_purpose,
          policy_area: bill&.policy_area, bill_url: bill&.congress_gov_url,
          votes: rcs.map { vote(_1, Array(positions[_1.id]), party) } }
      end
      # Most recent activity first; the writer is told how many were left out.
      shown = items.sort_by { |g| g[:votes].map { _1[:date] }.max }.reverse.first(MAX_VOTE_GROUPS)
      { total_roll_calls: roll_calls.size, by_chamber: roll_calls.map(&:chamber).tally, measures: items.size,
        measures_shown: shown.size, items: shown }
    end

    def vote(rc, rows, party)
      by_party = rows.group_by { _1[4] }
      breakdown = by_party.sort.to_h.transform_values { |rs| rs.map { _1[1] }.tally.slice(*Tally::POSITIONS) }
      majority = by_party.slice(*MAJOR_PARTIES).transform_values do |rs|
        yea, nay = rs.count { _1[1] == "Yea" }, rs.count { _1[1] == "Nay" }
        yea == nay ? nil : (yea > nay ? "Yea" : "Nay")
      end
      breakers = rows.select { |r| (m = majority[r[4]]) && %w[Yea Nay].include?(r[1]) && r[1] != m }
      pattern = pattern(majority, breakers.size)
      breakers = breakers.select { _1[4] == party } if party

      { roll_call_id: rc.id, number: rc.number, date: rc.voted_at&.to_date, question: rc.question, result: rc.result,
        yeas: rc.yeas, nays: rc.nays, source_url: rc.source_url, breakdown:, pattern:,
        broke_with_party: breakers.size,
        members_who_broke_with_party: breakers.sort_by { [ _1[4], _1[5], _1[3] ] }.map do |_, pos, id, name, pty, st, dist|
          { bioguide_id: id, name:, party: pty, state_code: st, district: dist, position: pos }
        end }
    end

    PARTY_LINE_MAX_BREAKS = 3

    # How the two major parties lined up, from each one's majority position and how many members broke from it.
    def pattern(majority, breaks)
      d, r = majority.values_at(*MAJOR_PARTIES)
      return "no clear party majority" unless d && r
      return "both parties mostly voted #{d}" if d == r

      kind = breaks <= PARTY_LINE_MAX_BREAKS ? "party-line" : "parties split"
      "#{kind}: Democrats mostly #{d}, Republicans mostly #{r}"
    end

    def title_for(rc, bills)
      bills[rc.bill_key]&.title || rc.topical_description
    end

    def introduced(from, chamber, party)
      scope = bill_scope(chamber).where(introduced_date: from..)
      sponsors = BillSponsorship.where(role: "sponsor", bill_id: scope.select(:id)).joins(:member)
      sponsors = sponsors.where(members: { party: }) if party
      rows = sponsors.pluck(:bill_id, "members.bioguide_id", "members.full_name", "members.party", "members.state_code",
                            "members.chamber", "members.district")
      bills = Bill.where(id: rows.map(&:first)).index_by(&:id)
      cosponsors = cosponsor_parties(bills.keys)

      notable = rows.sort_by { |r| [ -cosponsors[r[0]].size, -(bills[r[0]].introduced_date&.jd || 0) ] }.first(MAX_NOTABLE_BILLS)
      top = rows.group_by { _1[1] }.sort_by { |_, rs| [ -rs.size, rs.first[2] ] }.first(5)

      { total: rows.size,
        by_sponsor_party: rows.map { _1[3] }.tally,
        by_chamber: bills.values.map { _1.bill_type.start_with?("H") ? "house" : "senate" }.tally,
        top_policy_areas: bills.values.filter_map(&:policy_area).tally.sort_by { -_2 }.first(6).to_h,
        most_active_sponsors: top.map { |_, rs| member(rs.first, 1).merge(bills_introduced: rs.size) },
        most_cosponsored: notable.map do |r|
          bill_item(bills[r[0]]).merge(sponsor: member(r, 1), cosponsors: cosponsors[r[0]].size,
                                       cosponsor_parties: cosponsors[r[0]].tally)
        end }
    end

    def advanced(from, chamber, party)
      scope = bill_scope(chamber).where(latest_action_date: from..).where("introduced_date IS NULL OR introduced_date < ?", from)
      scope = scope.where(id: BillSponsorship.where(role: "sponsor").joins(:member).where(members: { party: }).select(:bill_id)) if party
      steps = scope.filter_map do |bill|
        rank = ADVANCING.index { |_, re| bill.latest_action_text.to_s.match?(re) } or next
        [ rank, bill ]
      end
      shown = steps.sort_by { |rank, b| [ rank, -b.latest_action_date.jd ] }.first(MAX_ADVANCED_BILLS)
      sponsors = BillSponsorship.where(role: "sponsor", bill_id: shown.map { _2.id }).joins(:member)
                                .pluck(:bill_id, "members.bioguide_id", "members.full_name", "members.party",
                                       "members.state_code", "members.chamber", "members.district").index_by(&:first)

      { total: steps.size, by_step: steps.map { ADVANCING[_1.first].first }.tally,
        items: shown.map do |rank, bill|
          bill_item(bill).merge(step: ADVANCING[rank].first, latest_action: bill.latest_action_text&.truncate(200),
                                latest_action_date: bill.latest_action_date, sponsor: sponsors[bill.id] && member(sponsors[bill.id], 1))
        end }
    end

    # The same data, one line per item, small enough for the writer's context window (the page shows the rest).
    def facts(activity)
      w, v, i, a = activity.values_at(:window, :votes, :introduced, :advanced)
      { window: "#{w[:from]} to #{w[:to]} (last #{w[:days]} days)#{" · #{w[:chamber]} only" if w[:chamber]}" \
                "#{" · #{w[:party]} members' bills and party breaks only" if w[:party]}",
        data_through: activity[:data_through],
        roll_call_votes: { total: v[:total_roll_calls], by_chamber: v[:by_chamber],
                           measures_voted_on: v[:measures], measures_listed: v[:measures_shown],
                           measures: v[:items].map { vote_line(_1) } },
        bills_introduced: i.except(:most_active_sponsors, :most_cosponsored).merge(
          most_active_sponsors: i[:most_active_sponsors].map { "#{who(_1)}: #{_1[:bills_introduced]}" },
          most_cosponsored: i[:most_cosponsored].map do |b|
            "#{b[:label]} (#{b[:introduced_date]}), sponsor #{who(b[:sponsor])}, #{b[:cosponsors]} cosponsors " \
              "#{b[:cosponsor_parties].map { |pty, n| "#{n} #{pty}" }.join(', ').presence&.then { "(#{_1})" }}: #{b[:title]}"
          end),
        older_bills_that_moved: { total: a[:total], by_step: a[:by_step],
                                  listed: a[:items].map { "#{_1[:label]} [#{_1[:step]} on #{_1[:latest_action_date]}], sponsor #{who(_1[:sponsor])}: #{_1[:title]}" } } }
    end

    def vote_line(group)
      votes = group[:votes].map do |vt|
        breaks = vt[:members_who_broke_with_party]
        names = breaks.size <= MAX_BREAKERS_LISTED ? breaks.map { who(_1) }.join(", ") : nil
        "#{vt[:date]} #{vt[:question]}: #{vt[:result]} #{vt[:yeas]}-#{vt[:nays]}, #{vt[:pattern]}" \
          "#{"; #{breaks.size} broke with their party#{" (#{names})" if names.present?}" if breaks.any?}"
      end
      "#{group[:chamber].capitalize} · #{[ group[:legislation], group[:title] ].compact.join(' — ')}" \
        "#{" — amendment: #{group[:amendment]}" if group[:amendment]} || #{votes.join(' | ')}"
    end

    def who(m) = m ? "#{m[:name]} (#{m[:party].to_s[0]}-#{m[:state_code]})" : "unknown"

    def bill_scope(chamber)
      return Bill.all unless chamber

      Bill.where(chamber == "house" ? "bill_type LIKE 'H%'" : "bill_type LIKE 'S%'")
    end

    def cosponsor_parties(bill_ids)
      BillSponsorship.where(role: "cosponsor", bill_id: bill_ids).joins(:member).pluck(:bill_id, "members.party")
                     .group_by(&:first).transform_values { |rs| rs.map(&:last) }.tap { _1.default = [] }
    end

    def bill_item(bill)
      { bill_id: bill.id, label: bill.label, title: bill.title&.truncate(200), policy_area: bill.policy_area,
        introduced_date: bill.introduced_date, url: bill.congress_gov_url }
    end

    # row: [_, bioguide_id, name, party, state_code, chamber, district], offset by `start`.
    def member(row, start)
      id, name, pty, st, ch, dist = row[start, 6]
      { bioguide_id: id, name:, party: pty, state_code: st, chamber: ch, district: dist }
    end
  end
end

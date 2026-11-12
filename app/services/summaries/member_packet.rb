module Summaries
  # Builds the compact, factual input the LLM summarizes. Everything the model may say must come from here,
  # so we pre-compute the numbers (party agreement, issue focus) in Ruby instead of asking a small local
  # model to count. Kept small on purpose: a CPU-only 14B model reads ~16 tokens/sec.
  class MemberPacket
    RECENT_SPONSORED = 12
    RECENT_COSPONSORED = 8
    PARTY_BREAKS = 8
    KEY_VOTES = 8

    def initialize(member)
      @member = member
    end

    def to_h
      @to_h ||= {
        member: member_info,
        committees: committees,
        legislation: legislation,
        voting: voting,
        data_scope: "Bills from the #{Congress::Client.current_congress}th Congress only; votes are the " \
                    "#{roll_call_ids.size} most recent #{chamber_name} roll calls synced into this app."
      }
    end

    # Changes whenever the underlying data changes, so we know when a saved summary is stale.
    def fingerprint
      Digest::SHA256.hexdigest(to_h.to_json)
    end

    private

    attr_reader :member

    def chamber_name = member.chamber == "senate" ? "Senate" : "House"

    def member_info
      seat = if member.chamber == "senate" then "Senator from #{member.state}"
      elsif member.district then "Representative for #{member.state} district #{member.district}"
      else "Representative for #{member.state} (at-large or delegate seat)"
      end
      # Only the current term's start is stored (not first election), so name it precisely; a field called
      # "serving_since" led the model to write "serving since 2025" for a senator first elected in 2018.
      { name: member.full_name, party: member.party, seat:, current_term_began: member.term_start_year }
    end

    def committees
      member.committee_memberships.includes(:committee).map do |cm|
        role = cm.title.presence
        name = cm.committee.parent_id ? "#{cm.committee.parent&.name} — #{cm.committee.name} (subcommittee)" : cm.committee.name
        role ? "#{name}: #{role}" : name
      end.sort
    end

    def legislation
      sponsored = bills_for("sponsor")
      cosponsored = bills_for("cosponsor")
      {
        sponsored_count: sponsored.count,
        cosponsored_count: cosponsored.count,
        top_policy_areas: Bill.joins(:bill_sponsorships).where(bill_sponsorships: { member_id: member.id })
                              .where.not(policy_area: nil).group(:policy_area).order(Arel.sql("COUNT(*) DESC"), :policy_area)
                              .limit(8).count.map { |area, n| "#{area} (#{n} bills)" },
        recent_sponsored: sponsored.limit(RECENT_SPONSORED).map { |b| bill_line(b) },
        recent_cosponsored: cosponsored.limit(RECENT_COSPONSORED).map { |b| bill_line(b) }
      }
    end

    def bills_for(role)
      Bill.joins(:bill_sponsorships).where(bill_sponsorships: { member_id: member.id, role: })
          .order(introduced_date: :desc, id: :desc)
    end

    def bill_line(bill)
      [ bill.label, bill.title&.truncate(160), bill.policy_area && "[#{bill.policy_area}]" ].compact.join(" — ")
    end

    def voting
      cast = positions.count { |p| %w[Yea Nay].include?(p.position) }
      agreements = positions.select { |p| party_majority[p.roll_call_id] && %w[Yea Nay].include?(p.position) }
      agreed = agreements.count { |p| p.position == party_majority[p.roll_call_id] }
      breaks = agreements.reject { |p| p.position == party_majority[p.roll_call_id] }

      {
        roll_calls_in_data: roll_call_ids.size,
        yea_or_nay_votes_cast: cast,
        missed_or_present: positions.size - cast,
        compared_with: "#{comparison_party} majority",
        agreed_with_party_majority_percent: agreements.any? ? (100.0 * agreed / agreements.size).round : nil,
        votes_against_party_majority: breaks.first(PARTY_BREAKS).map { |p| vote_line(p, party: party_majority[p.roll_call_id]) },
        recent_final_votes: positions.select { |p| p.roll_call.question.to_s =~ /passage|pass|nomination|conference report|veto/i }
                                     .first(KEY_VOTES).map { |p| vote_line(p) }
      }
    end

    def vote_line(p, party: nil)
      rc = p.roll_call
      what = [ rc.question, rc.legislation, rc.description&.truncate(120) ].compact.join(" — ")
      line = "#{rc.voted_at&.to_date}: #{what} → voted #{p.position}"
      line += " (#{comparison_party} majority voted #{party})" if party
      "#{line}; result: #{rc.result}"
    end

    def positions
      @positions ||= member.vote_positions.joins(:roll_call).includes(:roll_call)
                           .order("roll_calls.voted_at DESC, roll_calls.id DESC").to_a
    end

    def roll_call_ids = @roll_call_ids ||= positions.map(&:roll_call_id)

    # Independents are compared with Democrats, the party they caucus with in the 119th Congress.
    def comparison_party = member.party.to_s.start_with?("Independent") ? "Democratic" : member.party

    # roll_call_id => "Yea" / "Nay": how most of the comparison party voted. An exact tie has no majority.
    def party_majority
      @party_majority ||= VotePosition.joins(:member)
                                      .where(roll_call_id: roll_call_ids, position: %w[Yea Nay], members: { party: comparison_party })
                                      .group(:roll_call_id, :position).count
                                      .group_by { |(rc_id, _), _| rc_id }
                                      .filter_map { |rc_id, pairs|
                                        yea = pairs.sum { |(_, pos), n| pos == "Yea" ? n : 0 }
                                        nay = pairs.sum { |(_, pos), n| pos == "Nay" ? n : 0 }
                                        [ rc_id, yea > nay ? "Yea" : "Nay" ] unless yea == nay
                                      }.to_h
    end
  end
end

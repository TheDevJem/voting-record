module Ask
  # Distinct-member counts across every vote and bill in a result, for questions with a stance. A member "matches"
  # by voting the counted position on a vote, or by sponsoring/cosponsoring a bill judged to support the stance;
  # they're on the "opposite" side by voting the other way or backing a bill judged to work against it.
  module Combined
    module_function

    def call(result)
      by_votes, against_votes = Set.new, Set.new
      Array(result[:votes]).select { _1[:counts_as] }.each do |v|
        v[:members].each do |m|
          by_votes << m[:bioguide_id] if m[:position] == v[:counts_as]
          against_votes << m[:bioguide_id] if %w[Yea Nay].include?(m[:position]) && m[:position] != v[:counts_as]
        end
      end
      by_bills = sponsors(result, true)
      against_bills = sponsors(result, false)
      matching = by_votes | by_bills
      opposite = against_votes | against_bills

      counted_votes = Array(result[:votes]).select { _1[:counts_as] }
      every_vote = counted_votes.map { |v| v[:members].select { _1[:position] == v[:counts_as] }.map { _1[:bioguide_id] }.to_set }.reduce(:&)

      { distinct_members_matching_stance: matching.size,
        distinct_members_matching_by_votes: (by_votes.size if result[:votes]),
        distinct_members_matching_on_every_counted_vote: every_vote&.size,
        distinct_members_matching_by_bills: (by_bills.size if result[:bills]),
        distinct_members_on_the_opposite_side: opposite.size,
        distinct_members_on_both_sides: (matching & opposite).size }.compact
    end

    def sponsors(result, supports)
      Array(result[:bills]).select { _1[:supports] == supports }.flat_map { |b| b[:members].map { _1[:bioguide_id] } }.to_set
    end
  end
end

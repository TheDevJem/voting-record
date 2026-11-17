module Ask
  # Answers one question in five stages, reporting each through the block so the page can show progress:
  #   planning  - the model turns the question into a search plan (topic, party, stance)
  #   searching - hybrid search finds candidate votes and/or bills (Search::Retriever)
  #   reading   - the model judges which candidates fit, and which way each vote or bill points
  #   counting  - SQL tallies the party breakdowns and member lists (Ask::Tally)
  #   writing   - the model words a short answer from those computed facts
  class Pipeline
    class InvalidOutput < StandardError; end

    VOTE_CANDIDATES = 10
    BILL_CANDIDATES = 12

    def initialize(client: Summaries::OllamaClient.new(model: ENV["ASK_MODEL"].presence || ENV.fetch("OLLAMA_MODEL", "qwen3:14b")),
                   retriever: Search::Retriever.new)
      @client = client
      @retriever = retriever
      @stats = {}
    end

    def model = @client.model

    KINDS = %w[votes bills both].freeze

    # Returns { plan:, result:, answer:, stats: }. result: { kind:, votes: [...]?, bills: [...]?, bill_member_count:?,
    # role:?, rejected: [{ kind:, text:, reason: }] }.
    def call(question, &progress)
      progress ||= ->(_stage) { }

      progress.call("planning")
      plan = plan(question)
      want_votes = plan["kind"] != "bills"
      want_bills = plan["kind"] != "votes"

      progress.call("searching")
      search = ->(kind, limit) { @retriever.call(plan["search"], kind:, keywords: plan["keywords"], chamber: plan["chamber_filter"], limit:) }
      vote_docs = want_votes ? search.call("vote", VOTE_CANDIDATES) : []
      bill_docs = want_bills ? search.call("bill", BILL_CANDIDATES) : []

      progress.call("reading")
      votes, rejected_votes = want_votes ? read_votes(question, plan, vote_docs) : [ [], [] ]
      bills, rejected_bills = want_bills ? read_bills(question, plan, bill_docs) : [ [], [] ]

      progress.call("counting")
      result = { kind: plan["kind"], rejected: rejected_votes + rejected_bills }
      result[:votes] = Tally.votes(votes, party: plan["party_filter"]) if want_votes
      if want_bills
        tally = Tally.bills(bills, party: plan["party_filter"], role: plan["role_filter"])
        result.merge!(bills: tally[:items], bill_member_count: tally[:member_count], role: plan["role_filter"])
      end

      progress.call("writing")
      answer = write(question, plan, result)

      { plan:, result:, answer:, stats: @stats }
    end

    private

    def plan(question)
      plan = ask(:plan, Prompts::PLAN_SYSTEM, "Question: #{question}", Prompts::PLAN_SCHEMA)
      plan["kind"] = "votes" unless KINDS.include?(plan["kind"])
      plan["search"] = plan["search"].to_s.strip.presence || question
      plan["keywords"] = Array(plan["keywords"]).map(&:to_s).first(6)
      plan["party_filter"] = plan["party"] if Member.where(party: plan["party"]).exists?
      plan["chamber_filter"] = plan["chamber"] if Member::CHAMBERS.include?(plan["chamber"])
      plan["stance"] = plan["stance"].to_s.strip
      plan["role_filter"] = plan["role"] if %w[sponsor cosponsor].include?(plan["role"])
      plan
    end

    def read_votes(question, plan, docs)
      candidates = docs.each_with_index.map { |d, i| [ "V#{i + 1}", d ] }.to_h
      bills = RollCall.bills_for(candidates.values.map(&:record))
      meanings = candidates.transform_values { |doc| VoteMeaning.for(doc.record, bills[doc.record.bill_key]) }
      judged = judge(:read_votes, Prompts::READ_VOTES_SYSTEM, Prompts::READ_VOTES_SCHEMA, "votes", candidates,
                     "Question: #{question}\nStance: #{plan['stance'].presence || '(none: just how people voted)'}") do |ref, doc|
        "#{ref}: #{doc.content}\n    What a Yea means: #{meanings[ref]}"
      end

      chosen = candidates.filter_map do |ref, doc|
        j = judged[ref] or next
        next unless j["relevant"]

        counts_as = { "yes" => "Yea", "no" => "Nay" }[j["yea_supports_stance"]] if plan["stance"].present?
        { roll_call: doc.record, bill: bills[doc.record.bill_key], counts_as:, reason: j["reason"].to_s, meaning: meanings[ref] }
      end

      [ chosen, rejected("vote", candidates, judged) ]
    end

    def read_bills(question, plan, docs)
      candidates = docs.each_with_index.map { |d, i| [ "B#{i + 1}", d ] }.to_h
      judged = judge(:read_bills, Prompts::READ_BILLS_SYSTEM, Prompts::READ_BILLS_SCHEMA, "bills", candidates,
                     "Question: #{question}\nStance: #{plan['stance'].presence || '(none: just who sponsored what)'}")
      chosen = candidates.filter_map do |ref, doc|
        j = judged[ref]
        next unless j&.dig("relevant")

        supports = { "yes" => true, "no" => false }[j["sponsoring_supports_stance"]] if plan["stance"].present?
        { bill: doc.record, reason: j["reason"].to_s, supports: }
      end
      [ chosen, rejected("bill", candidates, judged) ]
    end

    # Asks the model about every candidate at once; returns { ref => judgment }. Unjudged candidates count as not relevant.
    def judge(step, system, schema, key, candidates, header)
      return {} if candidates.empty?

      listing = candidates.map { |ref, doc| block_given? ? yield(ref, doc) : "#{ref}: #{doc.content}" }.join("\n")
      data = ask(step, system, "#{header}\n\nCandidates:\n#{listing}", schema)
      Array(data[key]).select { _1.is_a?(Hash) }.index_by { _1["ref"].to_s }
    end

    def rejected(kind, candidates, judged)
      candidates.reject { |ref, _| judged.dig(ref, "relevant") }.map do |ref, doc|
        { kind:, text: doc.content.truncate(400), reason: judged.dig(ref, "reason").to_s.presence || "Not judged relevant." }
      end
    end

    def write(question, plan, result)
      answer = ask(:write, Prompts::WRITE_SYSTEM, "Question: #{question}\n\nFacts:\n#{JSON.pretty_generate(facts(plan, result))}",
                   Prompts::WRITE_SCHEMA)["answer"].to_s.strip
      without_missing_names_claim(answer)
    end

    # The writer only sees counts, and kept telling readers names aren't available, though the page lists them
    # right under the answer. Drop any sentence saying so.
    NAMES_UNAVAILABLE = /\b(?:names?|list)\b[^.]*\b(?:not|n't|unavailable|no)\b[^.]*\b(?:provide|available|include|list|given)|\bdoes(?: not|n't) (?:provide|include|list)[^.]*\bnames?\b/i

    def without_missing_names_claim(answer)
      kept = answer.split(/(?<=[.!?])\s+/).reject { |s| s.match?(NAMES_UNAVAILABLE) }
      kept.any? ? kept.join(" ") : answer
    end

    # A compact, number-complete view of the result for the writer (member lists are shown by the page instead).
    # Every cross-vote or cross-bill count is computed here, since the model must never add numbers up itself.
    def facts(plan, result)
      facts = { party_asked_about: plan["party_filter"] || "any", stance: plan["stance"].presence,
                member_names: "listed on the page directly under your answer" }
      facts.merge!(Combined.call(result)) if plan["stance"].present?
      if result[:votes]
        facts[:votes] = result[:votes].map do |v|
          { roll_call_vote: "#{v[:chamber].capitalize} roll call #{v[:number]} on #{v[:date]}: #{v[:question]}",
            legislation: [ v[:legislation], v[:title] ].compact.join(" — "), amendment: v.dig(:amendment, :purpose), result: v[:result],
            what_a_yea_means: v[:meaning], counted_as_matching_the_stance: v[:counts_as], why: v[:reason],
            positions_by_party: v[:breakdown], members_matching_stance_in_party_asked: v[:matching] }.compact
        end
      end
      if result[:bills]
        facts[:bill_role] = plan["role_filter"] || "sponsor or cosponsor"
        facts[:distinct_bill_sponsors_and_cosponsors] = result[:bill_member_count]
        facts[:bills] = result[:bills].map do |b|
          { sponsored_bill: "#{b[:label]} — #{b[:title]}", sponsoring_matches_stance: b[:supports], why: b[:reason],
            sponsors_and_cosponsors_by_party: b[:party_counts] }.compact
        end
      end
      facts
    end

    def ask(step, system, user, schema)
      response = @client.chat(system:, user:, format: schema)
      @stats[step] = response[:stats]
      JSON.parse(response[:content])
    rescue JSON::ParserError
      raise InvalidOutput, "The model's #{step} step didn't return valid JSON."
    end
  end
end

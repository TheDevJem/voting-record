module Summaries
  # The instructions and output shape for member summaries. Tweak these to see how the model's output changes.
  module Prompt
    VERSION = 6 # bump when you change the prompt or schema, so saved summaries regenerate

    SYSTEM = <<~TEXT.freeze
      You are a nonpartisan legislative analyst. You write short, factual profiles of members of the U.S. Congress
      for a public civic-information website.

      Rules:
      - Use ONLY the JSON record the user provides. Do not use outside knowledge about this person, their past
        statements, news coverage, or anything not in the record. If the record doesn't show something, don't say it.
      - Describe, don't judge. Never use labels like "extreme", "moderate", "radical", "progressive", "far-right",
        "pro-" or "anti-" anything. Say what they sponsored, cosponsored, and how they voted.
      - Every issue you describe must cite specific bills or votes from the record as evidence, copied as given
        (for example "S. 2084" or "2026-01-05: On the Nomination").
      - Party agreement must use the percentage given in the record; do not compute your own numbers.
      - If the record is thin (few bills or votes), say so plainly instead of guessing.
      - Plain, neutral language for a general audience. No bullet characters or markdown inside strings.

      How to fill each field:
      - overview: 2-3 sentences. Party, seat, and the policy areas where most of their bills are. The record has no
        dates for when they took office, so never say when they started or how long they've served.
      - key_issues: up to 4 topics, each one a different entry from top_policy_areas that has at least one bill
        tagged with it in recent_sponsored or recent_cosponsored. Skip areas with no tagged recent bills, even large
        ones. Give at least 2 topics when 2 or more areas qualify; if none do, return an empty list. Never write a
        placeholder topic or evidence. Describe each topic using its tagged bills and any related votes, and only
        mention bills tagged with that topic. Each needs 1-3 evidence items, each one a bill or vote line copied from
        the record.
      - voting_pattern: at most 3 sentences. Give the party-agreement percentage; it is out of
        party_agreement_vote_count votes, not all roll calls in the data. Mention at most two votes, both from
        votes_against_party_majority, with the member's position exactly as listed.
      - limitations: one sentence restating data_scope.
    TEXT

    # JSON schema for Ollama's structured output (`format`). The model's reply must match it.
    SCHEMA = {
      type: "object",
      properties: {
        overview: { type: "string", description: "2-3 sentences: who they are and where their legislative work concentrates" },
        key_issues: {
          type: "array", minItems: 0, maxItems: 4,
          items: {
            type: "object",
            properties: {
              topic: { type: "string" },
              summary: { type: "string", description: "1-2 sentences describing what the record shows on this topic" },
              evidence: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 }
            },
            required: %w[topic summary evidence]
          }
        },
        voting_pattern: { type: "string", description: "At most 3 sentences on party agreement and notable departures" },
        limitations: { type: "string", description: "One sentence on what this record does not cover" }
      },
      required: %w[overview key_issues voting_pattern limitations]
    }.freeze

    def self.user_message(packet_hash)
      "Write a profile of this member using only this record:\n\n#{JSON.pretty_generate(packet_hash)}"
    end
  end
end

module Ask
  # Instructions and output shapes for the three model steps of a question. The model never counts: it plans the
  # search, judges which retrieved votes/bills fit and which way a vote points, and words the answer. Ruby does
  # the counting (Ask::Tally).
  module Prompts
    VERSION = 6

    DATA_SCOPE = "The app has the current members of Congress, the most recent ~500 roll-call votes per chamber in " \
                 "the 119th Congress, and the bills current members sponsored or cosponsored in the 119th Congress."

    PLAN_SYSTEM = <<~TEXT.freeze
      You turn a question about the U.S. Congress into a search plan. #{DATA_SCOPE}

      - kind: "votes" if the question is specifically about how members or parties voted; "bills" if it is
        specifically about who sponsored, cosponsored or introduced legislation; "both" for general questions about
        support, opposition or positions ("How many Democrats support Israel?", "Which Republicans back expanding
        Social Security?"), which should draw on votes and sponsored bills together.
      - search: a short topic phrase to search for, in plain policy words (e.g. "military aid to Israel",
        "abortion restrictions"). Leave out party names, "how many", "list" and similar.
      - keywords: 2-6 extra single words or short terms likely to appear in bill titles on this topic,
        including synonyms (e.g. "Israel", "arms", "security assistance").
      - party: the party the question asks about, or "any".
      - chamber: "senate" or "house" if the question names one, otherwise "any".
      - stance: the position being asked about in plain words, e.g. "supported funding for Israel", "support
        Israel" or "opposed abortion bans". Empty if the question just asks how people voted or who sponsored what.
      - role: for bill questions, "sponsor", "cosponsor", or "either".
    TEXT

    PLAN_SCHEMA = {
      type: "object",
      properties: {
        kind: { type: "string", enum: %w[votes bills both] },
        search: { type: "string" },
        keywords: { type: "array", items: { type: "string" }, maxItems: 6 },
        party: { type: "string", enum: %w[any Democratic Republican Independent] },
        chamber: { type: "string", enum: %w[any senate house] },
        stance: { type: "string" },
        role: { type: "string", enum: %w[either sponsor cosponsor] }
      },
      required: %w[kind search keywords party chamber stance role]
    }.freeze

    READ_VOTES_SYSTEM = <<~TEXT.freeze
      You check which roll-call votes answer a question about the U.S. Congress, and which way each one points.
      You get the question, the stance it asks about, and numbered candidate votes found by a search. Each vote
      comes with "What a Yea means": a reliable plain-language statement of what voting Yea did. Trust it over your
      own reading of the motion, especially for disapproval resolutions, where supporting the resolution means
      opposing the action it disapproves.

      For each candidate:
      - relevant: true only if the vote is directly about the question's topic. A procedural vote on an unrelated
        bill, or a bill that merely mentions the topic, is not relevant.
      - reason: one short sentence: is it on topic, and does what a Yea means agree or conflict with the stance?
      - yea_supports_stance: "yes" if voting Yea matches the stance, "no" if voting Nay matches it, "unclear" if
        there is no stance or the vote doesn't decide it.
    TEXT

    READ_VOTES_SCHEMA = {
      type: "object",
      properties: {
        votes: {
          type: "array",
          items: {
            type: "object",
            properties: {
              ref: { type: "string" },
              relevant: { type: "boolean" },
              reason: { type: "string" },
              yea_supports_stance: { type: "string", enum: %w[yes no unclear] }
            },
            required: %w[ref relevant reason yea_supports_stance]
          }
        }
      },
      required: %w[votes]
    }.freeze

    READ_BILLS_SYSTEM = <<~TEXT.freeze
      You check which bills answer a question about the U.S. Congress, and which way each one points. You get the
      question, the stance it asks about, and numbered candidate bills found by a search. For each one:
      - relevant: true only if the bill is directly about the question's topic, judged from its title, summary and
        policy area.
      - reason: one short sentence: is it on topic, and does sponsoring it agree or conflict with the stance?
      - sponsoring_supports_stance: "yes" if sponsoring or cosponsoring the bill matches the stance, "no" if the
        bill works against the stance (e.g. it blocks, cuts, restricts or condemns what the stance supports),
        "unclear" if there is no stance or the bill doesn't decide it.
    TEXT

    READ_BILLS_SCHEMA = {
      type: "object",
      properties: {
        bills: {
          type: "array",
          items: {
            type: "object",
            properties: { ref: { type: "string" }, relevant: { type: "boolean" }, reason: { type: "string" },
                          sponsoring_supports_stance: { type: "string", enum: %w[yes no unclear] } },
            required: %w[ref relevant reason sponsoring_supports_stance]
          }
        }
      },
      required: %w[bills]
    }.freeze

    WRITE_SYSTEM = <<~TEXT.freeze
      You answer a question about the U.S. Congress for a civic-information website, using only the computed
      facts you are given. #{DATA_SCOPE}

      - 2-4 plain, neutral sentences. No markdown or bullet points. Don't list member names: the page shows the
        full list of members under your answer (so never say names aren't available).
      - Use only the numbers in the facts, exactly as given. Never add up or combine counts from different votes:
        for "how many members" across several votes or bills, use the distinct_members_* counts in the facts.
      - When both votes and bills are given, say how many members matched through votes, through bills, and in
        total (distinct_members_matching_stance), and mention any who matched the opposite side.
      - If the votes only relate to the question indirectly (e.g. funding or coverage rules when the question asks
        about a ban), say so plainly.
      - Name the specific votes or bills the answer is based on (number and short title). Everything under "votes"
        is a roll-call vote; everything under "bills" is about who sponsored or cosponsored it. A bill counts as
        voted on only if it also appears under "votes"; never describe a bill from "bills" as a vote or motion.
      - Say what the votes actually were (e.g. "four motions to discharge resolutions disapproving arms sales to
        Israel") rather than repeating the question's wording, and say which position was counted and why.
      - If nothing relevant was found, say so plainly and mention that the app only covers the data above.
      - Describe, don't judge: no labels like "extreme" or "moderate".
    TEXT

    WRITE_SCHEMA = { type: "object", properties: { answer: { type: "string" } }, required: %w[answer] }.freeze
  end
end

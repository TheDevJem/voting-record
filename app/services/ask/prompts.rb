module Ask
  # Instructions and output shapes for the model steps of a question. The model never counts: it plans the
  # search, judges which retrieved votes/bills fit and which way a vote points, and words the answer. Ruby does
  # the counting (Ask::Tally).
  module Prompts
    VERSION = 7

    DATA_SCOPE = "The app has the current members of Congress, the most recent ~500 roll-call votes per chamber in " \
                 "the 119th Congress, and the bills current members sponsored or cosponsored in the 119th Congress."

    FOLLOW_UP_RULE = "- If earlier questions in the conversation are shown, the new one may be a follow-up: answer what " \
                     "it asks in that light, without repeating earlier answers. The facts are only for the new question."

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
      - kind "activity" instead, for questions about what happened recently with no single topic ("Give me the
        highlights of the last 7 days", "What did the House do this week?", "What's new in Congress?"): the app
        then lists every vote, new bill and bill that moved in that window. Use party and chamber if the question
        names them; leave search as "recent activity", keywords empty and stance empty.
      - days: for "activity", how many days back the question covers: "this week" or "last 7 days" = 7, "today" =
        1, "this month" = 30, unspecified = 7. Any number from 1 to 90. For other kinds use 7.

      Follow-ups: if earlier questions in the conversation are shown, the new question may lean on them ("What about
      Republicans?", "And in the House?", "Which of those passed?", "List them", "What about last month?"). Carry
      over the earlier plan's kind, topic, keywords, stance, filters and days, changing only what the new question
      changes. After an "activity" question, a follow-up about who did what in that period ("What did Democrats
      introduce?", "What passed?", "Just the Senate?") stays "activity" with the new party or chamber. A question
      on a new topic gets a fresh plan.
    TEXT

    PLAN_SCHEMA = {
      type: "object",
      properties: {
        kind: { type: "string", enum: %w[votes bills both activity] },
        search: { type: "string" },
        keywords: { type: "array", items: { type: "string" }, maxItems: 6 },
        party: { type: "string", enum: %w[any Democratic Republican Independent] },
        chamber: { type: "string", enum: %w[any senate house] },
        stance: { type: "string" },
        role: { type: "string", enum: %w[either sponsor cosponsor] },
        days: { type: "integer", minimum: 1, maximum: 90 }
      },
      required: %w[kind search keywords party chamber stance role days]
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
      #{FOLLOW_UP_RULE}
    TEXT

    WRITE_ACTIVITY_SYSTEM = <<~TEXT.freeze
      You write a short digest of recent activity in the U.S. Congress for a civic-information website, using only
      the facts you are given: every roll-call vote in the window (grouped by the measure voted on), bills introduced
      in it, and older bills that moved forward in it. #{DATA_SCOPE} Bill actions only show each bill's latest step.

      - Plain text, no markdown or bullet points: 2-4 short paragraphs separated by a blank line, about 120-220
        words in all. The page lists every vote and bill under your answer, so pick the highlights.
      - Lead with what mattered most: bills that passed or were sent to the President, final votes on passage and
        confirmations, and close or party-line votes. Group related votes (a nomination's cloture and confirmation
        votes are one story). Then the new bills: how many, by which party, the main policy areas, and two or three
        of the most-cosponsored with their sponsors. Mention the most active sponsor if one stands out.
      - Say who did what: name sponsors as given (e.g. "Don Bacon (R-NE)"), say how each party voted and how many
        members broke with their party, and name them only when the facts list them.
      - Use only the numbers and dates in the facts, exactly as given; never add counts up yourself. Refer to votes
        by what they were on (e.g. "the Senate confirmed Daniel Domenico to the Tenth Circuit, 51-46").
      - If a window has no votes, or the data ends before the window does (data_through), say so plainly.
      - Describe, don't judge: no labels like "extreme", "controversial" or "moderate".
      #{FOLLOW_UP_RULE}
    TEXT

    WRITE_SCHEMA = { type: "object", properties: { answer: { type: "string" } }, required: %w[answer] }.freeze
  end
end

module Summaries
  # Automatic checks on one AI summary against the record (MemberPacket) it was written from. Each check
  # matches one rule in Prompt::SYSTEM, so a failure tells you which instruction the model ignored.
  #
  # These catch mistakes a program can see: made-up bill numbers, a wrong percentage, loaded labels, a broken
  # format. They can't tell whether a sentence fairly describes a bill or a vote, so still read some summaries.
  class Evaluation
    Result = Data.define(:name, :passed, :detail)

    # Bill labels as Bill#label writes them ("H.R. 1234", "S.J.Res. 7"), longest first so "S.Res." wins over "S.".
    BILL_ID = /(?<![\w.])(?:H\.Con\.Res\.|S\.Con\.Res\.|H\.J\.Res\.|S\.J\.Res\.|H\.Res\.|S\.Res\.|H\.R\.|S\.)\s?\d+/
    # Congress.gov's compact House-vote codes ("HRES 1247"), which older records and some summaries use. Bare "S"
    # is left out: "S 12" is too likely to be something else.
    COMPACT_BILL_ID = /\b(HCONRES|SCONRES|HJRES|SJRES|HRES|SRES|HR)\s?(\d+)\b/
    NOMINATION_ID = /\bPN\s?\d+(?:-\d+)?/
    DATE = /\b\d{4}-\d{2}-\d{2}\b/
    PERCENT = /(\d+(?:\.\d+)?)\s?(?:%|percent\b)/i
    LOADED_LABEL = /\b(?:extreme|extremist|moderate|radical|progressive|liberal|conservative|far-right|far-left|
                      hard-line|hardline|pro-[a-z]+|anti-[a-z]+)\b/ix
    # The record only has the current term's start year, so any claim about length of service is invented.
    # (In /x mode literal spaces are ignored, so word gaps are written as \s.)
    TENURE_CLAIM = /\b(?:serv(?:ing|ed)\ssince|in\soffice\ssince|since\s(?:19|20)\d{2}|first\selected|longtime|long-serving|
                     (?:current\s)?term\s(?:began|begins|started|starts|beginning|starting)|
                     (?:elected|re-elected|reelected|sworn\sin|took\soffice|(?:entered|joined)\s(?:the\s)?(?:senate|house|congress))
                       \s(?:in\s)?(?:19|20)\d{2}|
                     veteran\s(?:senator|lawmaker|legislator|congress(?:wo)?man)|
                     for\s(?:(?:over|more\sthan|nearly|almost)\s)?(?:\d+|two|three|four|five|six|seven|eight|nine|ten)\syears|
                     (?:\d+|two|three|four|five|six|seven|eight|nine|ten)[-\s]term)\b/ix
    # Periods that don't end a sentence, so "U.S. Senate" or "Keith R. Sonderling" count as one sentence.
    NOT_SENTENCE_END = /\b(?:U\.S|H\.R|H\.J\.Res|S\.J\.Res|H\.Res|S\.Res|H\.Con\.Res|S\.Con\.Res|S\.Amdt|H\.Amdt|
                         Sen|Rep|Mr|Ms|Mrs|Dr|Jr|Sr|St|No|vs|[A-Z])\./x
    # "S. 12 — Rural Clinics Act — [Health]": the policy-area tag MemberPacket puts at the end of each bill line.
    AREA_TAG = /\[([^\]]+)\]\s*\z/
    VOTE_LINE = /\A\W*\d{4}-\d{2}-\d{2}:/
    MARKDOWN = /(?:\A|\n)\s*(?:[-*•]|\d+\.)\s|\*\*|__|`|^#/

    def self.normalize(text)
      text.to_s.downcase.tr("—–‐‑", "----").tr("’‘“”", "''\"\"").gsub("…", "...").squish
    end

    def initialize(content, input)
      @content = JSON.parse(content.to_json) # string keys, whether it came from the database or the generator
      @input = JSON.parse(input.to_json)
    end

    def results
      @results ||= [
        evidence_grounded, cited_ids_exist, party_agreement, party_breaks_from_record, neutral_language, no_tenure_claim,
        topics_from_policy_areas, evidence_on_topic, limitations_match_scope, format
      ]
    end

    def score = results.count(&:passed).fdiv(results.size)
    def failures = results.reject(&:passed)

    def to_h = { score: score.round(3), checks: results.map(&:to_h) }

    private

    attr_reader :content, :input

    # Every evidence item should be copied from the record. "Exact" means it appears word for word; "loose" means
    # it was reworded but every bill, nomination and date in it is real. Anything else is made up, including a real
    # bill number paired with a title the record doesn't give it ("S. 12 — Some Other Act").
    def evidence_grounded
      items = issues.flat_map { |i| Array(i["evidence"]) }
      if items.empty?
        thin = issues.empty? && policy_areas.empty?
        return result(:evidence_grounded, thin, thin ? "no key issues (record has no policy areas)" : "no evidence items")
      end

      graded = items.map { |e| [ e, grade(e) ] }
      counts = graded.map(&:last).tally
      bad = graded.select { |_, g| g == :ungrounded }.map(&:first)
      retitled = graded.select { |_, g| g == :wrong_title }.map(&:first)
      placeholders = graded.select { |_, g| g == :not_a_citation }.map(&:first)
      detail = "#{counts[:exact].to_i} exact, #{counts[:loose].to_i} reworded, #{bad.size} not in record"
      detail += ", #{retitled.size} with the wrong title" if retitled.any?
      detail += ", #{placeholders.size} not a bill or vote" if placeholders.any?
      flagged = bad + retitled + placeholders
      detail += ": #{flagged.map(&:inspect).join('; ')}" if flagged.any?
      result(:evidence_grounded, flagged.empty?, detail)
    end

    def grade(evidence)
      text = self.class.normalize(evidence).delete_prefix('"').delete_suffix('"')
      found = ids_in(evidence, dates: true)
      # Copied text that names no bill, nomination or date ("International Affairs (61 bills)") isn't evidence.
      return :not_a_citation if found.empty? && (packet_text.include?(text) || !evidence.to_s.match?(/\d/))
      return :exact if packet_text.include?(text)
      return :ungrounded unless found.any? && (found - packet_ids).empty?

      title_matches?(evidence) ? :loose : :wrong_title
    end

    # Evidence shaped like a bill line ("<number> — <title> ..."): the title must be the one the record gives that
    # number. Free-form rewordings ("Sponsored S. 12 on clinics") have no title to compare and pass.
    def title_matches?(evidence)
      number, title = evidence.to_s.delete_prefix('"').split(/\s+[—–-]\s+/, 3)
      id = number.to_s.strip.delete(" ")
      return true unless title && (id.match?(/\A#{BILL_ID}\z/) || id.match?(/\A#{NOMINATION_ID}\z/))

      title = self.class.normalize(title.sub(AREA_TAG, "")).delete_suffix("...").strip
      title.empty? || lines_citing(id).any? { |line| self.class.normalize(line).include?(title) }
    end

    # Bill and nomination numbers anywhere in the summary, including the prose, must exist in the record.
    def cited_ids_exist
      cited = ids_in(all_text, dates: false).uniq
      missing = cited - packet_ids
      detail = missing.any? ? "not in record: #{missing.join(', ')}" : "#{cited.size} cited, all in record"
      result(:cited_ids_exist, missing.empty?, detail)
    end

    # The prompt says to copy the record's percentage, never compute one.
    def party_agreement
      expected = input.dig("voting", "agreed_with_party_majority_percent")
      found = content["voting_pattern"].to_s.scan(PERCENT).flatten.map(&:to_f).uniq
      if expected.nil?
        result(:party_agreement, found.empty?, found.empty? ? "record has no percentage" : "invented #{found.join(', ')}%")
      elsif found != [ expected.to_f ]
        result(:party_agreement, false, "record says #{expected}%, summary says #{found.any? ? found.map { "#{_1}%" }.join(', ') : 'nothing'}")
      elsif (wrong = wrong_agreement_base).any?
        result(:party_agreement, false, "#{expected}% is out of #{agreement_base} votes, summary says out of #{wrong.join(', ')}")
      else
        result(:party_agreement, true, "#{expected}% as given")
      end
    end

    # The percentage is out of party_agreement_vote_count votes (ones where the member and their party's majority
    # both voted Yea or Nay), not every roll call. Any "N roll calls" / "N votes" after the percentage in the same
    # sentence must be that number. Records saved before the field existed skip this.
    def agreement_base = input.dig("voting", "party_agreement_vote_count")

    def wrong_agreement_base
      return [] unless agreement_base

      text = content["voting_pattern"].to_s
      start = text.index(PERCENT) or return []
      clause = text[start..][/\A.*?(?:[.!?](?=\s|\z)|\z)/m]
      clause.scan(/(\d[\d,]*)\s(?:\w+\s)?(?:roll[\s-]calls?|votes)\b/i).flatten.map { _1.delete(",").to_i }.uniq - [ agreement_base.to_i ]
    end

    # voting_pattern should mention at most two votes, both from votes_against_party_majority, with the member's
    # position as the record gives it ("voted Nay on S. 4668" when the record says they voted Yea fails).
    def party_breaks_from_record
      breaks = Array(input.dig("voting", "votes_against_party_majority")).map(&:to_s)
      text = content["voting_pattern"].to_s
      cited = ids_in(text, dates: false).uniq
      problems = []

      not_breaks = cited.reject { |id| breaks.any? { |b| ids_in(b, dates: false).include?(id) } }
      problems << "not in votes_against_party_majority: #{not_breaks.join(', ')}" if not_breaks.any?
      problems << "#{cited.size} votes mentioned (want at most 2)" if cited.size > 2

      (cited - not_breaks).each do |id|
        said = stated_position(text, id) or next
        actual = breaks.select { |b| ids_in(b, dates: false).include?(id) }.filter_map { |b| b[/→ voted (\w+)/, 1] }.uniq
        problems << "says #{said} on #{id}, record says #{actual.join('/')}" unless actual.include?(said)
      end
      result(:party_breaks_from_record, problems.empty?,
             problems.any? ? problems.join("; ") : "#{cited.size} cited, all from votes_against_party_majority")
    end

    # "He voted Nay on the passage of S. 4668" -> "Nay". Only looks just before the number, and skips the party's own
    # position ("while the majority voted Yea").
    def stated_position(text, id)
      compact = RollCall::BILL_TYPE_LABELS.key(id[/\A\D+/])
      forms = [ id.sub(/\d/) { "\\s?#{_1}" }.gsub(".", "\\."), (compact && "\\b#{compact}\\s?#{id[/\d.*/]}") ].compact
      at = text.index(Regexp.new(forms.join("|"))) or return nil
      before = text[[ at - 90, 0 ].max...at]
      match = before.to_enum(:scan, /(?<!majority\s)(?<!majority\shad\s)\bvoted\s(yea|nay)\b/i).map { Regexp.last_match }.last
      match && match[1].capitalize
    end

    def neutral_language
      hits = phrases_not_in_record(prose, LOADED_LABEL)
      result(:neutral_language, hits.empty?, hits.any? ? "labels: #{hits.join(', ')}" : "no loaded labels")
    end

    def no_tenure_claim
      hits = phrases_not_in_record(prose, TENURE_CLAIM)
      result(:no_tenure_claim, hits.empty?, hits.any? ? "claims: #{hits.join(', ')}" : "no length-of-service claims")
    end

    def topics_from_policy_areas
      if policy_areas.empty?
        listed = issues.map { |i| i["topic"].to_s }
        return result(:topics_from_policy_areas, listed.empty?,
                      listed.empty? ? "record has no policy areas, none listed" : "record has no policy areas but lists: #{listed.join(', ')}")
      end

      topics = issues.map { |i| i["topic"].to_s }
      off = topics.reject { |t| policy_area_match?(t) }
      bare = (topics - off).reject { |t| eligible_areas.any? { |a| same_area?(a, t) } }
      problems = []
      problems << "not a top policy area: #{off.join(', ')}" if off.any?
      problems << "no recent bills tagged: #{bare.join(', ')}" if bare.any?
      result(:topics_from_policy_areas, problems.empty?, problems.any? ? problems.join("; ") : "all topics are top policy areas with tagged bills")
    end

    # Bills in the record end with their policy area, e.g. "— [Health]". Bill evidence for a topic should carry
    # that topic's tag. This is strict: a veterans' health bill tagged "Armed Forces" fails under "Health".
    # Evidence the model wrote without the tag ("S. 40") is checked against the tag the record gives that bill, and a
    # bill the record gives no policy area can't be a "matching bill" for any topic. Votes are exempt.
    def evidence_on_topic
      off = issues.flat_map do |i|
        Array(i["evidence"]).filter_map do |e|
          area, id = evidence_area(e)
          if area == :untagged
            "#{id} (no policy area in the record) under \"#{i['topic']}\""
          elsif area && !same_area?(area, i["topic"])
            "#{area} evidence under \"#{i['topic']}\""
          end
        end
      end
      result(:evidence_on_topic, off.empty?, off.any? ? off.join("; ") : "bill evidence matches its topic")
    end

    # [area, bill id]: the evidence's own tag, else the record's tag for the first bill it names, :untagged when the
    # record's line for that bill has none, or nil when there's nothing to check (a vote, an unknown bill).
    def evidence_area(evidence)
      text = evidence.to_s
      return [ text[AREA_TAG, 1], nil ] if text.match?(AREA_TAG)
      return nil if text.match?(VOTE_LINE)

      id = text.scan(BILL_ID).first&.delete(" ") or return nil
      line = bill_lines.find { |l| ids_in(l, dates: false).first == id } or return nil
      [ line[AREA_TAG, 1] || :untagged, id ]
    end

    # data_scope gives the Congress and the number of roll calls; the limitations sentence should repeat both.
    def limitations_match_scope
      numbers = input["data_scope"].to_s.scan(/\d+/)
      missing = numbers.reject { |n| content["limitations"].to_s.match?(/\b#{n}/) }
      result(:limitations_match_scope, missing.empty?, missing.any? ? "doesn't mention #{missing.join(', ')}" : "matches data_scope")
    end

    def format
      problems = []
      wanted = issue_range
      problems << "#{issues.size} key issues (want #{wanted.minmax.uniq.join('-')})" unless wanted.cover?(issues.size)
      topics = issues.map { |i| self.class.normalize(i["topic"]) }
      problems << "duplicate topics: #{topics.tally.select { |_, n| n > 1 }.keys.join(', ')}" if topics.uniq.size < topics.size
      issues.each do |i|
        n = Array(i["evidence"]).size
        problems << "#{n} evidence items for \"#{i['topic']}\" (want 1-3)" unless n.between?(1, 3)
      end
      overview = sentences(content["overview"])
      problems << "overview has #{overview} sentences (want 2-3)" unless overview.between?(2, 3)
      voting = sentences(content["voting_pattern"])
      problems << "voting_pattern has #{voting} sentences (want at most 3)" if voting > 3
      problems << "markdown or bullets in text" if strings.any? { |s| s.match?(MARKDOWN) }
      result(:format, problems.empty?, problems.any? ? problems.join("; ") : "lengths and counts as asked")
    end

    def result(name, passed, detail) = Result.new(name:, passed:, detail:)

    # Up to 4 topics, one per qualifying policy area (a top area with at least one tagged recent bill): at least 2
    # when 2 or more qualify, none when none do.
    def issue_range = eligible_areas.size.clamp(0, 2)..eligible_areas.size.clamp(0, 4)

    def eligible_areas
      @eligible_areas ||= begin
        tags = bill_lines.filter_map { |l| l[AREA_TAG, 1] }
        policy_areas.select { |a| tags.any? { |t| same_area?(a, t) } }
      end
    end

    def issues = Array(content["key_issues"]).select { |i| i.is_a?(Hash) }

    # Everything the model wrote, and just the prose (not the copied evidence).
    def strings = [ content["overview"], content["voting_pattern"], content["limitations"],
                    *issues.flat_map { |i| [ i["topic"], i["summary"], *Array(i["evidence"]) ] } ].map(&:to_s)
    def all_text = strings.join("\n")
    def prose = [ content["overview"], content["voting_pattern"], *issues.map { |i| i["summary"] } ].join("\n")

    def packet_strings = @packet_strings ||= collect_strings(input)
    def packet_text = @packet_text ||= self.class.normalize(packet_strings.join("\n"))
    def packet_ids = @packet_ids ||= ids_in(packet_strings.join("\n"), dates: true).uniq
    def lines_citing(id) = packet_strings.select { |line| ids_in(line, dates: false).include?(id) }
    def bill_lines = @bill_lines ||= %w[recent_sponsored recent_cosponsored].flat_map { |k| Array(input.dig("legislation", k)).map(&:to_s) }

    def collect_strings(value)
      case value
      when Hash then value.values.flat_map { |v| collect_strings(v) }
      when Array then value.flat_map { |v| collect_strings(v) }
      else [ value.to_s ]
      end
    end

    def ids_in(text, dates:)
      text = text.to_s
      ids = text.scan(BILL_ID) + text.scan(COMPACT_BILL_ID).map { |type, n| "#{RollCall::BILL_TYPE_LABELS[type]}#{n}" } +
            text.scan(NOMINATION_ID)
      ids += text.scan(DATE) if dates
      ids.map { |id| id.delete(" ") }
    end

    # Matches of `pattern` in `text`, ignoring ones the record itself contains (a bill titled "...Progressive...").
    def phrases_not_in_record(text, pattern)
      text.to_s.scan(pattern).map { |m| m.is_a?(Array) ? m.first : m }.map(&:downcase).uniq
          .reject { |m| packet_text.include?(self.class.normalize(m)) }
    end

    def policy_areas = @policy_areas ||= Array(input.dig("legislation", "top_policy_areas")).map { |a| a.sub(/\s*\(\d+ bills?\)\z/, "") }
    def policy_area_match?(topic) = policy_areas.any? { |area| same_area?(area, topic) }

    # Exact match after normalizing case, "&" and a trailing bill count. Substring matching let "Law" pass as
    # "Crime and Law Enforcement", which are different Congress.gov policy areas.
    def same_area?(a, b)
      a, b = [ a, b ].map { |x| self.class.normalize(x).gsub("&", "and").sub(/\s*\(\d+ bills?\)\z/, "").squish }
      a.present? && a == b
    end

    def sentences(text)
      text.to_s.gsub(NOT_SENTENCE_END) { |m| m.delete(".") }
          .split(/(?<=[.!?])["')\]]*\s+(?=["'(]?[A-Z0-9])/).count(&:present?)
    end
  end
end

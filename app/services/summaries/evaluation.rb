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
    NOMINATION_ID = /\bPN\s?\d+(?:-\d+)?/
    DATE = /\b\d{4}-\d{2}-\d{2}\b/
    PERCENT = /(\d+(?:\.\d+)?)\s?(?:%|percent\b)/i
    LOADED_LABEL = /\b(?:extreme|extremist|moderate|radical|progressive|liberal|conservative|far-right|far-left|
                      hard-line|hardline|pro-[a-z]+|anti-[a-z]+)\b/ix
    # The record only has the current term's start year, so any claim about length of service is invented.
    # (In /x mode literal spaces are ignored, so word gaps are written as \s.)
    TENURE_CLAIM = /\b(?:serv(?:ing|ed)\ssince|in\soffice\ssince|since\s(?:19|20)\d{2}|first\selected|longtime|long-serving|
                     veteran\s(?:senator|lawmaker|legislator|congress(?:wo)?man)|
                     for\s(?:(?:over|more\sthan|nearly|almost)\s)?(?:\d+|two|three|four|five|six|seven|eight|nine|ten)\syears|
                     (?:\d+|two|three|four|five|six|seven|eight|nine|ten)[-\s]term)\b/ix
    # Periods that don't end a sentence, so "U.S. Senate" or "Keith R. Sonderling" count as one sentence.
    NOT_SENTENCE_END = /\b(?:U\.S|H\.R|H\.J\.Res|S\.J\.Res|H\.Res|S\.Res|H\.Con\.Res|S\.Con\.Res|S\.Amdt|H\.Amdt|
                         Sen|Rep|Mr|Ms|Mrs|Dr|Jr|Sr|St|No|vs|[A-Z])\./x
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
        evidence_grounded, cited_ids_exist, party_agreement, neutral_language, no_tenure_claim,
        topics_from_policy_areas, evidence_on_topic, limitations_match_scope, format
      ]
    end

    def score = results.count(&:passed).fdiv(results.size)
    def failures = results.reject(&:passed)

    def to_h = { score: score.round(3), checks: results.map(&:to_h) }

    private

    attr_reader :content, :input

    # Every evidence item should be copied from the record. "Exact" means it appears word for word; "loose" means
    # it was reworded but every bill, nomination and date in it is real. Anything else is made up.
    def evidence_grounded
      items = issues.flat_map { |i| Array(i["evidence"]) }
      return result(:evidence_grounded, false, "no evidence items") if items.empty?

      graded = items.map { |e| [ e, grade(e) ] }
      bad = graded.select { |_, g| g == :ungrounded }.map(&:first)
      counts = graded.map(&:last).tally
      detail = "#{counts[:exact].to_i} exact, #{counts[:loose].to_i} reworded, #{bad.size} not in record"
      detail += ": #{bad.map(&:inspect).join('; ')}" if bad.any?
      result(:evidence_grounded, bad.empty?, detail)
    end

    def grade(evidence)
      text = self.class.normalize(evidence).delete_prefix('"').delete_suffix('"')
      return :exact if packet_text.include?(text)

      found = ids_in(evidence, dates: true)
      found.any? && (found - packet_ids).empty? ? :loose : :ungrounded
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
      else
        ok = found == [ expected.to_f ]
        result(:party_agreement, ok, ok ? "#{expected}% as given" : "record says #{expected}%, summary says #{found.any? ? found.map { "#{_1}%" }.join(', ') : 'nothing'}")
      end
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
      return result(:topics_from_policy_areas, true, "record has no policy areas") if policy_areas.empty?

      off = issues.map { |i| i["topic"].to_s }.reject { |t| policy_area_match?(t) }
      result(:topics_from_policy_areas, off.empty?, off.any? ? "not a top policy area: #{off.join(', ')}" : "all topics are top policy areas")
    end

    # Bills in the record end with their policy area, e.g. "— [Health]". Evidence for a topic should be tagged
    # with that topic. This is strict: a veterans' health bill tagged "Armed Forces" fails under "Health".
    def evidence_on_topic
      off = issues.flat_map do |i|
        Array(i["evidence"]).filter_map do |e|
          tag = e.to_s[/\[([^\]]+)\]\s*\z/, 1]
          "#{tag} evidence under \"#{i['topic']}\"" if tag && !same_area?(tag, i["topic"])
        end
      end
      result(:evidence_on_topic, off.empty?, off.any? ? off.join("; ") : "tagged evidence matches its topic")
    end

    # data_scope gives the Congress and the number of roll calls; the limitations sentence should repeat both.
    def limitations_match_scope
      numbers = input["data_scope"].to_s.scan(/\d+/)
      missing = numbers.reject { |n| content["limitations"].to_s.match?(/\b#{n}/) }
      result(:limitations_match_scope, missing.empty?, missing.any? ? "doesn't mention #{missing.join(', ')}" : "matches data_scope")
    end

    def format
      problems = []
      problems << "#{issues.size} key issues (want 2-4)" unless issues.size.between?(2, 4)
      issues.each do |i|
        n = Array(i["evidence"]).size
        problems << "#{n} evidence items for \"#{i['topic']}\" (want 1-4)" unless n.between?(1, 4)
      end
      overview = sentences(content["overview"])
      problems << "overview has #{overview} sentences (want 2-3)" unless overview.between?(2, 3)
      voting = sentences(content["voting_pattern"])
      problems << "voting_pattern has #{voting} sentences (want at most 3)" if voting > 3
      problems << "markdown or bullets in text" if strings.any? { |s| s.match?(MARKDOWN) }
      result(:format, problems.empty?, problems.any? ? problems.join("; ") : "lengths and counts as asked")
    end

    def result(name, passed, detail) = Result.new(name:, passed:, detail:)

    def issues = Array(content["key_issues"]).select { |i| i.is_a?(Hash) }

    # Everything the model wrote, and just the prose (not the copied evidence).
    def strings = [ content["overview"], content["voting_pattern"], content["limitations"],
                    *issues.flat_map { |i| [ i["topic"], i["summary"], *Array(i["evidence"]) ] } ].map(&:to_s)
    def all_text = strings.join("\n")
    def prose = [ content["overview"], content["voting_pattern"], *issues.map { |i| i["summary"] } ].join("\n")

    def packet_strings = @packet_strings ||= collect_strings(input)
    def packet_text = @packet_text ||= self.class.normalize(packet_strings.join("\n"))
    def packet_ids = @packet_ids ||= ids_in(packet_strings.join("\n"), dates: true).uniq

    def collect_strings(value)
      case value
      when Hash then value.values.flat_map { |v| collect_strings(v) }
      when Array then value.flat_map { |v| collect_strings(v) }
      else [ value.to_s ]
      end
    end

    def ids_in(text, dates:)
      ids = text.to_s.scan(BILL_ID) + text.to_s.scan(NOMINATION_ID)
      ids += text.to_s.scan(DATE) if dates
      ids.map { |id| id.delete(" ") }
    end

    # Matches of `pattern` in `text`, ignoring ones the record itself contains (a bill titled "...Progressive...").
    def phrases_not_in_record(text, pattern)
      text.to_s.scan(pattern).map { |m| m.is_a?(Array) ? m.first : m }.map(&:downcase).uniq
          .reject { |m| packet_text.include?(self.class.normalize(m)) }
    end

    def policy_areas = @policy_areas ||= Array(input.dig("legislation", "top_policy_areas")).map { |a| a.sub(/\s*\(\d+ bills?\)\z/, "") }
    def policy_area_match?(topic) = policy_areas.any? { |area| same_area?(area, topic) }

    def same_area?(a, b)
      a, b = self.class.normalize(a), self.class.normalize(b)
      a.present? && b.present? && (a == b || a.include?(b) || b.include?(a))
    end

    def sentences(text)
      text.to_s.gsub(NOT_SENTENCE_END) { |m| m.delete(".") }
          .split(/(?<=[.!?])["')\]]*\s+(?=["'(]?[A-Z0-9])/).count(&:present?)
    end
  end
end

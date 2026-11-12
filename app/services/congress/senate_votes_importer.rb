module Congress
  # The most recent Senate roll-call votes from senate.gov's public XML (Congress.gov has no Senate votes).
  # Senators are matched to Congress.gov members by state code + last name (unique among current senators).
  class SenateVotesImporter
    BASE = "https://www.senate.gov/legislative/LIS".freeze
    TZ = "Eastern Time (US & Canada)".freeze

    def initialize(congress: Client.current_congress, limit: 100, log: ->(msg) { puts msg })
      @congress = congress
      @limit = limit
      @log = log
    end

    def call
      recent = [ 2, 1 ].flat_map { |session| menu(session) }.first(@limit)
      members = Member.where(chamber: "senate").to_h { |m| [ match_key(m.state_code, m.last_name), m.id ] }

      imported = 0
      recent.each do |session, number|
        key = { chamber: "senate", congress: @congress, session:, number: }
        next if RollCall.joins(:vote_positions).exists?(key)

        doc = Nokogiri::XML(Http.get(format("%s/roll_call_votes/vote%d%d/vote_%d_%d_%05d.xml", BASE, @congress, session, @congress, session, number)))
        text = ->(path) { doc.at_xpath("//roll_call_vote/#{path}")&.text&.squish.presence }

        positions = doc.xpath("//members/member").filter_map do |m|
          member_id = members[match_key(m.at("state").text, m.at("last_name").text)]
          [ member_id, m.at("vote_cast").text.squish ] if member_id
        end

        Congress::RollCallWriter.write(
          key.merge(voted_at: Time.find_zone(TZ).parse(text.call("vote_date").to_s.delete(",")),
                    question: text.call("question") || text.call("vote_question_text"),
                    description: text.call("vote_document_text") || text.call("vote_title"),
                    result: text.call("vote_result"),
                    legislation: [ text.call("document/document_type"), text.call("document/document_number") ].compact.join(" ").presence,
                    source_url: "https://www.senate.gov/legislative/LIS/roll_call_votes/vote#{@congress}#{session}/vote_#{@congress}_#{session}_#{format('%05d', number)}.htm",
                    yeas: text.call("count/yeas")&.to_i, nays: text.call("count/nays")&.to_i),
          positions
        )
        imported += 1
      end
      @log.call("Senate votes: #{imported} new of #{recent.size} most recent")
    end

    private

    def match_key(state, last_name)
      [ state.to_s.upcase, I18n.transliterate(last_name.to_s).downcase.gsub(/[^a-z]/, "") ]
    end

    # [[session, vote_number], ...] newest first
    def menu(session)
      xml = Http.get("#{BASE}/roll_call_lists/vote_menu_#{@congress}_#{session}.xml")
      Nokogiri::XML(xml).xpath("//votes/vote/vote_number").map { |n| [ session, n.text.to_i ] }.sort_by { -_2 }
    rescue Http::NotFound
      [] # session hasn't started yet
    end
  end
end

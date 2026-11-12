module Congress
  # The most recent House roll-call votes (and every member's position) from Congress.gov.
  class HouseVotesImporter
    def initialize(client: Client.new, congress: Client.current_congress, limit: 100, log: ->(msg) { puts msg })
      @client = client
      @congress = congress
      @limit = limit
      @log = log
    end

    def call
      votes = []
      @client.each_page("/house-vote/#{@congress}", "houseRollCallVotes") { |items| votes.concat(items) }
      recent = votes.sort_by { |v| v["startDate"].to_s }.last(@limit).reverse
      members = Member.where(chamber: "house").pluck(:bioguide_id, :id).to_h

      imported = 0
      recent.each do |vote|
        key = { chamber: "house", congress: vote["congress"], session: vote["sessionNumber"], number: vote["rollCallNumber"] }
        next if RollCall.joins(:vote_positions).exists?(key) # already synced

        detail = @client.get("/house-vote/#{key[:congress]}/#{key[:session]}/#{key[:number]}/members", limit: 500)
                        .fetch("houseRollCallVoteMemberVotes")
        positions = detail["results"].filter_map do |r|
          member_id = members[r["bioguideID"]]
          [ member_id, normalize(r["voteCast"]) ] if member_id
        end

        legislation = [ detail["legislationType"], detail["legislationNumber"] ].compact.join(" ").presence
        Congress::RollCallWriter.write(
          key.merge(voted_at: detail["startDate"], question: detail["voteQuestion"], result: detail["result"],
                    description: detail["voteType"], legislation:, source_url: self.class.readable_url(detail["sourceDataURL"])),
          positions
        )
        imported += 1
      end
      @log.call("House votes: #{imported} new of #{recent.size} most recent")
    end

    # The API's sourceDataURL is the Clerk's raw XML (clerk.house.gov/evs/2026/roll221.xml); link people to the
    # readable vote page instead (clerk.house.gov/Votes/2026221).
    def self.readable_url(xml_url)
      match = xml_url.to_s.match(%r{/evs/(\d{4})/roll0*(\d+)\.xml\z})
      match ? "https://clerk.house.gov/Votes/#{match[1]}#{match[2]}" : xml_url
    end

    private

    def normalize(cast) = { "Aye" => "Yea", "No" => "Nay" }.fetch(cast, cast)
  end
end

module Congress
  # Current House + Senate members, entirely from Congress.gov. The member list gives each member's
  # chamber (from their latest term); the member detail endpoint adds state code and office contact info.
  # Members no longer serving are removed.
  class MembersImporter
    CHAMBERS = { "House of Representatives" => "house", "Senate" => "senate" }.freeze

    def initialize(client: Client.new, log: ->(msg) { puts msg })
      @client = client
      @log = log
    end

    def call
      seen = []
      @client.each_page("/member", "members", currentMember: true) do |items|
        items.each do |item|
          chamber = CHAMBERS[Array(item.dig("terms", "item")).last&.dig("chamber")]
          next unless chamber

          seen << item["bioguideId"]
          upsert(chamber, item, @client.get("/member/#{item['bioguideId']}").fetch("member"))
        end
      end

      removed = Member.where.not(bioguide_id: seen).destroy_all.size
      @log.call("Members: #{seen.size} current (#{removed} removed)")
    end

    private

    def upsert(chamber, item, detail)
      term = Array(detail["terms"]).last || {}
      address = detail["addressInformation"] || {}

      Member.find_or_initialize_by(bioguide_id: detail["bioguideId"]).update!(
        chamber: chamber,
        first_name: detail["firstName"],
        last_name: detail["lastName"],
        full_name: detail["directOrderName"].presence || [ detail["firstName"], detail["lastName"] ].compact.join(" "),
        party: item["partyName"],
        state: detail["state"],
        state_code: term["stateCode"],
        district: chamber == "house" ? detail["district"] : nil,
        image_url: detail.dig("depiction", "imageUrl"),
        website_url: detail["officialWebsiteUrl"],
        office_address: address["officeAddress"]&.squish,
        phone: address["phoneNumber"],
        term_start_year: term["startYear"]
      )
    end
  end
end

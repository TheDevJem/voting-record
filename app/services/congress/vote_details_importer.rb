require "nokogiri"

module Congress
  # Fills in descriptive text for voted-on legislation, so votes can be found by topic and read correctly:
  # - House amendment votes: the amendment's number, author and purpose (the vote record only names the bill).
  # - Every bill that was voted on: its CRS summary, plus a bill row for the few no current member sponsored.
  # Incremental: each roll call is looked up once, and summaries are refreshed after SUMMARY_TTL.
  class VoteDetailsImporter
    SUMMARY_TTL = 30.days # CRS adds new summaries as a bill advances
    AMENDMENT_LABELS = { "HAMDT" => "H.Amdt.", "SAMDT" => "S.Amdt." }.freeze

    def initialize(client: Client.new, log: ->(msg) { puts msg })
      @client = client
      @log = log
    end

    def call
      house_amendments
      voted_bills
    end

    private

    def house_amendments
      scope = RollCall.where(chamber: "house", details_fetched_at: nil).where("question ILIKE ?", "%amendment%")
      found = 0
      scope.find_each do |rc|
        vote = @client.get("/house-vote/#{rc.congress}/#{rc.session}/#{rc.number}")["houseRollCallVote"] || {}
        type, number = vote["amendmentType"], vote["amendmentNumber"]
        attrs = { details_fetched_at: Time.current }
        if type.present? && number.present?
          amendment = @client.get("/amendment/#{rc.congress}/#{type.downcase}/#{number}")["amendment"] || {}
          attrs.merge!(amendment_label: "#{AMENDMENT_LABELS.fetch(type.upcase, type)} #{number}", amendment_author: vote["amendmentAuthor"],
                       amendment_purpose: (amendment["purpose"].presence || amendment["description"]).to_s.squish.presence)
          found += 1
        end
        rc.update!(attrs)
      rescue Http::NotFound
        rc.update!(details_fetched_at: Time.current)
      end
      @log.call("House amendment votes: #{found} described")
    end

    def voted_bills
      keys = RollCall.where.not(legislation: nil).to_a.filter_map(&:bill_key).uniq
      known = RollCall.bills_for(RollCall.where.not(legislation: nil).to_a)
      (keys - known.keys).each { |key| create_bill(*key) }

      due = Bill.where(id: RollCall.bills_for(RollCall.where.not(legislation: nil).to_a).values.map(&:id))
                .where("summary_fetched_at IS NULL OR summary_fetched_at < ?", SUMMARY_TTL.ago)
      refreshed = 0
      due.find_each do |bill|
        bill.update!(summary: latest_summary(bill), summary_fetched_at: Time.current)
        refreshed += 1
      end
      @log.call("Voted bills: #{keys.size} total, #{(keys - known.keys).size} added, #{refreshed} summaries checked")
    end

    def create_bill(congress, type, number)
      b = @client.get("/bill/#{congress}/#{type.downcase}/#{number}")["bill"] || {}
      Bill.create!(congress:, bill_type: type, number:, title: b["title"], introduced_date: b["introducedDate"],
                   latest_action_text: b.dig("latestAction", "text"), latest_action_date: b.dig("latestAction", "actionDate"),
                   policy_area: b.dig("policyArea", "name"))
    rescue Http::NotFound
      nil
    end

    # The most recent CRS summary as plain text ("<p><strong>Major Richard Star Act</strong></p><p>This bill...").
    def latest_summary(bill)
      summaries = @client.get("/bill/#{bill.congress}/#{bill.bill_type.downcase}/#{bill.number}/summaries")["summaries"]
      latest = Array(summaries).max_by { |s| [ s["actionDate"].to_s, s["updateDate"].to_s ] } or return nil
      Nokogiri::HTML5.fragment(latest["text"].to_s.gsub(%r{</p>}, "</p> ")).text.squish.presence
    rescue Http::NotFound
      nil
    end
  end
end

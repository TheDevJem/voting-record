module Congress
  # Sponsored and cosponsored legislation for each current member, from Congress.gov.
  # Only bills from `min_congress` onward are kept (default: the current Congress) to keep the sync
  # time and request count down (each 250-item page takes Congress.gov several seconds). Amendments are skipped.
  class BillsImporter
    ROLES = { "sponsor" => %w[sponsored-legislation sponsoredLegislation],
              "cosponsor" => %w[cosponsored-legislation cosponsoredLegislation] }.freeze

    def initialize(client: Client.new, min_congress: Client.current_congress, log: ->(msg) { puts msg })
      @client = client
      @min_congress = min_congress
      @log = log
    end

    def call(members = Member.order(:last_name))
      total = members.size
      members.each_with_index do |member, i|
        counts = ROLES.to_h { |role, (path, key)| [ role, import(member, role, path, key) ] }
        @log.call("Bills [#{i + 1}/#{total}] #{member.full_name}: #{counts['sponsor']} sponsored, #{counts['cosponsor']} cosponsored")
      end
    end

    private

    def import(member, role, path, key)
      bill_ids = []
      @client.each_page("/member/#{member.bioguide_id}/#{path}", key) do |items|
        bills = items.select { |b| b["type"].present? && b["number"].present? && b["congress"].to_i >= @min_congress }
        bill_ids.concat(upsert_bills(bills, role)) if bills.any?
        # Results are newest first, so once a page is entirely older than min_congress we can stop.
        :stop if items.all? { |b| b["congress"].to_i < @min_congress }
      end

      BillSponsorship.transaction do
        member.bill_sponsorships.where(role:).where.not(bill_id: bill_ids).delete_all
        now = Time.current
        rows = bill_ids.uniq.map { |bill_id| { member_id: member.id, bill_id:, role:, created_at: now, updated_at: now } }
        BillSponsorship.upsert_all(rows, unique_by: %i[member_id bill_id role]) if rows.any?
      end
      bill_ids.uniq.size
    end

    # The same bill shows up in many members' lists, and those lists disagree:
    # - In a member's *cosponsored* list, Congress.gov's "introducedDate" is the date that member cosponsored,
    #   not the date the bill was introduced. Only the sponsor's list has the real introduced date, so cosponsor
    #   lists may fill it in for a new bill but never overwrite it.
    # - Some entries omit fields (e.g. policy area), so never replace a known value with a blank one.
    # Without these rules, values flip back and forth as the sync visits each cosponsor.
    def upsert_bills(items, role)
      now = Time.current
      rows = items.map do |b|
        { congress: b["congress"], bill_type: b["type"].upcase, number: b["number"].to_s, title: b["title"],
          introduced_date: b["introducedDate"], latest_action_text: b.dig("latestAction", "text"),
          latest_action_date: b.dig("latestAction", "actionDate"), policy_area: b.dig("policyArea", "name"),
          created_at: now, updated_at: now }
      end.uniq { |r| r.values_at(:congress, :bill_type, :number) }

      introduced = role == "sponsor" ? "COALESCE(EXCLUDED.introduced_date, bills.introduced_date)" \
                                     : "COALESCE(bills.introduced_date, EXCLUDED.introduced_date)"
      keep_known = %w[title latest_action_text latest_action_date policy_area]
                   .map { |col| "#{col} = COALESCE(EXCLUDED.#{col}, bills.#{col})" }.join(", ")

      Bill.upsert_all(rows, unique_by: %i[congress bill_type number],
                            on_duplicate: Arel.sql("introduced_date = #{introduced}, #{keep_known}"),
                            record_timestamps: false, returning: :id).rows.flatten
    end
  end
end

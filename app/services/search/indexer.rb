module Search
  # Builds one SearchDocument per roll call and per bill, and embeds any whose text changed. Safe to re-run: after the
  # first full run (~40 minutes for ~20k bills on CPU) only new or changed records are embedded.
  class Indexer
    def initialize(embedder: Embedder.new, log: $stdout)
      @embedder = embedder
      @log = log
    end

    def call
      index("vote", RollCall.all.to_a) { |rc, bills| vote_text(rc, bills) }
      index("bill", Bill.all.to_a) { |bill, _| bill_text(bill) }
      remove_orphans
    end

    SUMMARY_CHARS = 700 # keeps a document well inside nomic-embed-text's 2,048-token window

    def vote_text(rc, bills)
      bill = bills[rc.bill_key]
      chamber = rc.chamber == "senate" ? "Senate" : "House"
      what = [ rc.legislation_label, bill&.title || rc.topical_description ].compact.join(": ")
      amendment = rc.amendment_purpose && "Amendment #{[ rc.amendment_label, rc.amendment_sponsor && "(#{rc.amendment_sponsor})" ].compact.join(' ')}: " \
                                          "#{rc.amendment_purpose.delete_suffix('.')}."
      # An amendment vote is about the amendment, not the whole bill: a 3,000-page NDAA summary would drown it out.
      summary = bill&.summary && !rc.amendment_purpose && "Bill summary: #{bill.summary.truncate(SUMMARY_CHARS)}"
      [ "#{chamber} roll call #{rc.number} on #{rc.voted_at&.to_date}: #{rc.question}.", (what.presence && "#{what.delete_suffix('.')}."),
        amendment, (bill&.policy_area && "Policy area: #{bill.policy_area}."), (rc.result && "Result: #{rc.result}."), summary ]
        .compact.join(" ")
    end

    def bill_text(bill)
      [ "#{bill.label}: #{bill.title.to_s.delete_suffix('.')}.", (bill.policy_area && "Policy area: #{bill.policy_area}."),
        (bill.latest_action_text && "Latest action: #{bill.latest_action_text.delete_suffix('.')}."),
        (bill.summary && "Summary: #{bill.summary.truncate(SUMMARY_CHARS)}") ].compact.join(" ")
    end

    private

    def index(kind, records)
      type = records.first&.class&.name or return
      bills = kind == "vote" ? RollCall.bills_for(records) : {}
      existing = SearchDocument.where(record_type: type).pluck(:record_id, :content_digest).to_h

      rows = records.filter_map do |record|
        content = yield(record, bills)
        digest = Digest::SHA256.hexdigest(content)
        next if existing[record.id] == digest

        { record_type: type, record_id: record.id, kind:, chamber: (record.chamber if kind == "vote"), content:, content_digest: digest }
      end
      @log.puts "#{kind}s: #{records.size} total, #{rows.size} to embed"

      done = 0
      rows.each_slice(Embedder::BATCH * 4) do |slice|
        vectors = @embedder.documents(slice.map { _1[:content] })
        now = Time.current
        SearchDocument.upsert_all(slice.zip(vectors).map { |row, v| row.merge(embedding: v, created_at: now, updated_at: now) },
                                  unique_by: %i[record_type record_id], update_only: %i[kind chamber content content_digest embedding])
        done += slice.size
        @log.puts "  #{done}/#{rows.size}" if rows.size > Embedder::BATCH * 4
      end
    end

    # Records removed by a sync (e.g. bills of members who left office).
    def remove_orphans
      { "RollCall" => RollCall, "Bill" => Bill }.each do |type, model|
        SearchDocument.where(record_type: type).where.not(record_id: model.select(:id)).delete_all
      end
    end
  end
end

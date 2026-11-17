namespace :congress do
  desc "Sync everything: members, committees, bills, and recent votes (VOTE_LIMIT=500, BILL_MIN_CONGRESS=current), then the search index"
  task sync: %i[members committees votes bills vote_details] do
    # Keep the question box's index current. Only new or changed votes and bills are embedded, so this is quick
    # after the first run. Without Ollama the sync still succeeds; run `bin/rails search:index` later.
    Search::Indexer.new.call
  rescue Summaries::OllamaClient::Unavailable, Summaries::OllamaClient::Error => e
    warn "Skipped the search index (#{e.message}). Run bin/rails search:index once Ollama is running."
  end

  desc "Describe voted-on legislation: House amendment purposes and CRS bill summaries (incremental)"
  task vote_details: :environment do
    Congress::VoteDetailsImporter.new.call
  end

  desc "Sync current House and Senate members"
  task members: :environment do
    Congress::MembersImporter.new.call
  end

  desc "Sync committee and subcommittee assignments"
  task committees: :environment do
    Congress::CommitteesImporter.new.call
  end

  desc "Sync sponsored/cosponsored bills (BILL_MIN_CONGRESS defaults to the current Congress)"
  task bills: :environment do
    min = ENV.fetch("BILL_MIN_CONGRESS", Congress::Client.current_congress).to_i
    Congress::BillsImporter.new(min_congress: min).call
  end

  desc "Sync the most recent House and Senate roll-call votes (VOTE_LIMIT per chamber, default 100)"
  task votes: :environment do
    limit = ENV.fetch("VOTE_LIMIT", 100).to_i
    Congress::SenateVotesImporter.new(limit:).call
    Congress::HouseVotesImporter.new(limit:).call
  end
end

namespace :congress do
  desc "Sync everything: members, committees, bills, and recent votes (VOTE_LIMIT=100, BILL_MIN_CONGRESS=current)"
  task sync: %i[members committees votes bills]

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
    limit = ENV.fetch("VOTE_LIMIT", 500).to_i
    Congress::HouseVotesImporter.new(limit:).call
    Congress::SenateVotesImporter.new(limit:).call
  end
end

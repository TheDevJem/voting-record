module Congress
  # Committee + subcommittee assignments from the public unitedstates/congress-legislators dataset
  # (Congress.gov's API does not expose committee membership).
  class CommitteesImporter
    BASE = "https://raw.githubusercontent.com/unitedstates/congress-legislators/main".freeze

    def initialize(log: ->(msg) { puts msg })
      @log = log
    end

    def call
      committees = YAML.safe_load(Http.get("#{BASE}/committees-current.yaml"))
      assignments = YAML.safe_load(Http.get("#{BASE}/committee-membership-current.yaml"))
      members = Member.pluck(:bioguide_id, :id).to_h

      Committee.transaction do
        CommitteeMembership.delete_all
        by_code = import_committees(committees)

        rows = assignments.flat_map do |code, people|
          committee_id = by_code[code]
          next [] unless committee_id

          people.filter_map do |person|
            member_id = members[person["bioguide"]]
            next unless member_id

            { member_id:, committee_id:, title: person["title"], side: person["party"], rank: person["rank"],
              created_at: Time.current, updated_at: Time.current }
          end
        end
        CommitteeMembership.insert_all(rows.uniq { |r| [ r[:member_id], r[:committee_id] ] }) if rows.any?
        @log.call("Committees: #{by_code.size} committees, #{rows.size} assignments")
      end
    end

    private

    def import_committees(committees)
      by_code = {}
      committees.each do |c|
        parent = save(c["thomas_id"], c["name"], c["type"], c["url"], nil)
        by_code[parent.code] = parent.id
        Array(c["subcommittees"]).each do |sub|
          child = save("#{c['thomas_id']}#{sub['thomas_id']}", sub["name"], c["type"], nil, parent.id)
          by_code[child.code] = child.id
        end
      end
      by_code
    end

    def save(code, name, chamber, url, parent_id)
      Committee.find_or_initialize_by(code:).tap do |committee|
        committee.update!(name:, chamber:, url:, parent_id:)
      end
    end
  end
end

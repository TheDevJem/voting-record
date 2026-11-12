module Congress
  module RollCallWriter
    module_function

    # attrs: roll call columns; positions: [[member_id, "Yea"], ...]
    def write(attrs, positions)
      RollCall.transaction do
        roll_call = RollCall.find_or_initialize_by(attrs.slice(:chamber, :congress, :session, :number))
        tally = positions.map(&:last).tally
        roll_call.update!(attrs.reverse_merge(yeas: tally.fetch("Yea", 0), nays: tally.fetch("Nay", 0)))

        now = Time.current
        rows = positions.uniq(&:first).map do |member_id, position|
          { roll_call_id: roll_call.id, member_id:, position:, created_at: now, updated_at: now }
        end
        VotePosition.upsert_all(rows, unique_by: %i[member_id roll_call_id], update_only: %i[position]) if rows.any?
      end
    end
  end
end

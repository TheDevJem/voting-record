class AddInputToMemberSummaries < ActiveRecord::Migration[8.1]
  def change
    # The exact data packet sent to the model, for transparency and for debugging staleness.
    add_column :member_summaries, :input, :jsonb
  end
end

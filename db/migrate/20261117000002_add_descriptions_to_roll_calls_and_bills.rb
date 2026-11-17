class AddDescriptionsToRollCallsAndBills < ActiveRecord::Migration[8.1]
  def change
    # House amendment votes only name the bill being amended ("H.R. 8800"); these say what the amendment did.
    add_column :roll_calls, :amendment_label, :string    # "H.Amdt. 266"
    add_column :roll_calls, :amendment_author, :string   # "Grothman of Wisconsin Part A Amendment No. 316"
    add_column :roll_calls, :amendment_purpose, :text    # "Amendment sought to require the Secretary of Defense to..."
    add_column :roll_calls, :details_fetched_at, :datetime

    # The Congressional Research Service's plain-language summary, for bills that were voted on.
    add_column :bills, :summary, :text
    add_column :bills, :summary_fetched_at, :datetime
  end
end

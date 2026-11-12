class CreateCongressTables < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.string :bioguide_id, null: false
      t.string :chamber, null: false # "house" | "senate"
      t.string :first_name
      t.string :last_name
      t.string :full_name, null: false
      t.string :party
      t.string :state
      t.string :state_code
      t.integer :district
      t.string :image_url
      t.string :website_url
      t.string :office_address
      t.string :phone
      t.integer :term_start_year
      t.timestamps
    end
    add_index :members, :bioguide_id, unique: true
    add_index :members, [ :chamber, :last_name ]

    create_table :committees do |t|
      t.string :code, null: false # thomas id, e.g. HSAG or HSAG15 for a subcommittee
      t.string :name, null: false
      t.string :chamber, null: false # "house" | "senate" | "joint"
      t.string :url
      t.references :parent, foreign_key: { to_table: :committees }
      t.timestamps
    end
    add_index :committees, :code, unique: true

    create_table :committee_memberships do |t|
      t.references :member, null: false, foreign_key: true
      t.references :committee, null: false, foreign_key: true
      t.string :title
      t.string :side # "majority" | "minority"
      t.integer :rank
      t.timestamps
    end
    add_index :committee_memberships, [ :member_id, :committee_id ], unique: true

    create_table :bills do |t|
      t.integer :congress, null: false
      t.string :bill_type, null: false
      t.string :number, null: false
      t.text :title
      t.date :introduced_date
      t.text :latest_action_text
      t.date :latest_action_date
      t.string :policy_area
      t.timestamps
    end
    add_index :bills, [ :congress, :bill_type, :number ], unique: true

    create_table :bill_sponsorships do |t|
      t.references :member, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true
      t.string :role, null: false # "sponsor" | "cosponsor"
      t.timestamps
    end
    add_index :bill_sponsorships, [ :member_id, :bill_id, :role ], unique: true

    create_table :roll_calls do |t|
      t.string :chamber, null: false
      t.integer :congress, null: false
      t.integer :session, null: false
      t.integer :number, null: false
      t.datetime :voted_at
      t.string :question
      t.text :description
      t.string :result
      t.string :legislation
      t.string :source_url
      t.integer :yeas
      t.integer :nays
      t.timestamps
    end
    add_index :roll_calls, [ :chamber, :congress, :session, :number ], unique: true
    add_index :roll_calls, :voted_at

    create_table :vote_positions do |t|
      t.references :roll_call, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :position, null: false # Yea, Nay, Present, Not Voting
      t.timestamps
    end
    add_index :vote_positions, [ :member_id, :roll_call_id ], unique: true
  end
end

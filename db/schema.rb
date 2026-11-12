# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_11_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bill_sponsorships", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.bigint "bill_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bill_id"], name: "index_bill_sponsorships_on_bill_id"
    t.index ["member_id", "bill_id", "role"], name: "index_bill_sponsorships_on_member_id_and_bill_id_and_role", unique: true
    t.index ["member_id"], name: "index_bill_sponsorships_on_member_id"
  end

  create_table "bills", force: :cascade do |t|
    t.integer "congress", null: false
    t.string "bill_type", null: false
    t.string "number", null: false
    t.text "title"
    t.date "introduced_date"
    t.text "latest_action_text"
    t.date "latest_action_date"
    t.string "policy_area"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["congress", "bill_type", "number"], name: "index_bills_on_congress_and_bill_type_and_number", unique: true
  end

  create_table "committee_memberships", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.bigint "committee_id", null: false
    t.string "title"
    t.string "side"
    t.integer "rank"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["committee_id"], name: "index_committee_memberships_on_committee_id"
    t.index ["member_id", "committee_id"], name: "index_committee_memberships_on_member_id_and_committee_id", unique: true
    t.index ["member_id"], name: "index_committee_memberships_on_member_id"
  end

  create_table "committees", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "chamber", null: false
    t.string "url"
    t.bigint "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_committees_on_code", unique: true
    t.index ["parent_id"], name: "index_committees_on_parent_id"
  end

  create_table "member_summaries", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "content"
    t.string "fingerprint"
    t.string "model"
    t.jsonb "stats"
    t.text "error"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "input"
    t.index ["member_id"], name: "index_member_summaries_on_member_id", unique: true
  end

  create_table "members", force: :cascade do |t|
    t.string "bioguide_id", null: false
    t.string "chamber", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "full_name", null: false
    t.string "party"
    t.string "state"
    t.string "state_code"
    t.integer "district"
    t.string "image_url"
    t.string "website_url"
    t.string "office_address"
    t.string "phone"
    t.integer "term_start_year"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bioguide_id"], name: "index_members_on_bioguide_id", unique: true
    t.index ["chamber", "last_name"], name: "index_members_on_chamber_and_last_name"
  end

  create_table "roll_calls", force: :cascade do |t|
    t.string "chamber", null: false
    t.integer "congress", null: false
    t.integer "session", null: false
    t.integer "number", null: false
    t.datetime "voted_at"
    t.string "question"
    t.text "description"
    t.string "result"
    t.string "legislation"
    t.string "source_url"
    t.integer "yeas"
    t.integer "nays"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chamber", "congress", "session", "number"], name: "idx_on_chamber_congress_session_number_ea78bcfd9d", unique: true
    t.index ["voted_at"], name: "index_roll_calls_on_voted_at"
  end

  create_table "vote_positions", force: :cascade do |t|
    t.bigint "roll_call_id", null: false
    t.bigint "member_id", null: false
    t.string "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "roll_call_id"], name: "index_vote_positions_on_member_id_and_roll_call_id", unique: true
    t.index ["member_id"], name: "index_vote_positions_on_member_id"
    t.index ["roll_call_id"], name: "index_vote_positions_on_roll_call_id"
  end

  add_foreign_key "bill_sponsorships", "bills"
  add_foreign_key "bill_sponsorships", "members"
  add_foreign_key "committee_memberships", "committees"
  add_foreign_key "committee_memberships", "members"
  add_foreign_key "committees", "committees", column: "parent_id"
  add_foreign_key "member_summaries", "members"
  add_foreign_key "vote_positions", "members"
  add_foreign_key "vote_positions", "roll_calls"
end

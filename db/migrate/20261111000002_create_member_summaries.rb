class CreateMemberSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :member_summaries do |t|
      t.references :member, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "pending" # pending | running | complete | failed
      t.jsonb :content # the validated model output (overview, key_issues, voting_pattern, limitations)
      t.string :fingerprint # MemberPacket fingerprint + prompt version the content was generated from
      t.string :model
      t.jsonb :stats # token counts and timings reported by Ollama
      t.text :error
      t.datetime :generated_at
      t.timestamps
    end
  end
end

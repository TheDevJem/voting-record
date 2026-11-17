class CreateSearchDocumentsAndQuestions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    # One searchable text per roll call and per bill, for the question box (see Search::Indexer).
    create_table :search_documents do |t|
      t.references :record, polymorphic: true, null: false, index: false
      t.string :kind, null: false # "vote" or "bill"
      t.string :chamber           # votes only
      t.text :content, null: false
      t.string :content_digest, null: false # re-embed only when the text changes
      t.vector :embedding, limit: 768       # nomic-embed-text
      t.virtual :searchable, type: :tsvector, as: "to_tsvector('english', content)", stored: true
      t.timestamps
    end
    add_index :search_documents, %i[record_type record_id], unique: true
    add_index :search_documents, :kind
    add_index :search_documents, :searchable, using: :gin
    add_index :search_documents, :embedding, using: :hnsw, opclass: :vector_cosine_ops

    create_table :questions do |t|
      t.string :token, null: false, index: { unique: true } # public id, so questions aren't guessable by number
      t.text :text, null: false
      t.string :status, null: false, default: "pending" # pending, running, complete, failed
      t.string :stage                                    # while running: planning, searching, reading, counting, writing
      t.jsonb :plan
      t.jsonb :result
      t.text :answer
      t.string :model
      t.jsonb :stats
      t.text :error
      t.timestamps
    end
  end
end

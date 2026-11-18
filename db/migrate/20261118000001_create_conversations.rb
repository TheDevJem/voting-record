# Questions in the "Ask" box belong to a conversation, so follow-ups ("what about Republicans?") can use what came
# before. Existing questions each become a one-question conversation.
class CreateConversations < ActiveRecord::Migration[8.1]
  def up
    create_table :conversations do |t|
      t.string :token, null: false, index: { unique: true }
      t.timestamps
    end
    add_reference :questions, :conversation, foreign_key: true

    execute <<~SQL
      INSERT INTO conversations (token, created_at, updated_at)
      SELECT 'c-' || token, created_at, updated_at FROM questions;
      UPDATE questions SET conversation_id = conversations.id
      FROM conversations WHERE conversations.token = 'c-' || questions.token;
    SQL
    change_column_null :questions, :conversation_id, false
  end

  def down
    remove_reference :questions, :conversation
    drop_table :conversations
  end
end

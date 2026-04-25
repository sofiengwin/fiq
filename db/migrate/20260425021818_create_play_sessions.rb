class CreatePlaySessions < ActiveRecord::Migration[8.1]
  def change
    create_table :play_sessions do |t|
      t.string :session_id, null: false
      t.references :user, null: true, foreign_key: true
      t.string :quiz_type, default: "random"
      t.jsonb :questions, default: []
      t.jsonb :responses, default: []
      t.integer :current_index, default: 0
      t.integer :total_score, default: 0
      t.integer :streak, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :play_sessions, :session_id
    add_index :play_sessions, [ :session_id, :completed_at ]
  end
end

class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :quiz, null: false, foreign_key: true
      t.references :inviter_user, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false

      t.timestamps
    end

    add_index :invitations, [ :quiz_id, :inviter_user_id ], unique: true
    add_index :invitations, :token, unique: true
  end
end

class AddQuizPlayAndInvitationFields < ActiveRecord::Migration[8.1]
  def change
    add_column :answer_options, :image_url, :string
    add_reference :quiz_attempts, :user, foreign_key: true
    add_reference :quiz_attempts, :invitation, foreign_key: true
    add_column :quizzes, :generation_metadata, :jsonb, default: {}
    add_column :questions, :question_type, :string, default: "multiple_choice"
    add_column :questions, :payload, :jsonb, default: {}
    add_column :responses, :text_answer, :text
    add_column :responses, :payload, :jsonb, default: {}
  end
end

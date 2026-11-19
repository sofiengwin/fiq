require "test_helper"

# Q1 — Schema foundations for play + invitations (no behavior change).
# Derived from quiz-tickets.md Q1 "Done when" (not from implementation):
#   - Migration(s): answer_options.image_url nullable; quiz_attempts.user_id
#     nullable FK -> users + index; quiz_attempts.invitation_id nullable
#     FK -> invitations + index; quizzes.generation_metadata jsonb default {};
#     questions.question_type default multiple_choice + payload jsonb
#     default {}; responses.text_answer nullable + payload jsonb default {}.
#   - invitations: quiz_id FK, inviter_user_id FK -> users, token unique
#     not-null, unique index (quiz_id, inviter_user_id) + unique token.
#   - quizzes.scoring_mode untouched; no minutes_played.
class Q1SchemaFoundationsTest < ActiveSupport::TestCase
  def columns(table)
    ActiveRecord::Base.connection.columns(table).index_by(&:name)
  end

  def index_names(table)
    ActiveRecord::Base.connection.indexes(table).map(&:name)
  end

  def unique_index_names(table)
    ActiveRecord::Base.connection.indexes(table).select(&:unique).map(&:name)
  end

  def foreign_keys(table)
    ActiveRecord::Base.connection.foreign_keys(table)
  end

  # Rails reports a jsonb {} default as the serialized string "{}".
  def assert_jsonb_empty_default(col, label)
    default = col.is_a?(ActiveRecord::ConnectionAdapters::Column) ? col.default : col
    parsed = default.is_a?(String) ? JSON.parse(default) : default
    assert_equal({}, parsed, "#{label} must default to {}")
  end

  def q1_user(email)
    User.create!(email_address: email, password: "password123")
  end

  def q1_quiz(title)
    Quiz.create!(title: title)
  end

  def q1_invitation_row(quiz_id:, inviter_user_id:, token:)
    conn = ActiveRecord::Base.connection
    now = conn.quote(Time.current)
    conn.execute(<<~SQL)
      INSERT INTO invitations (quiz_id, inviter_user_id, token, created_at, updated_at)
      VALUES (#{quiz_id}, #{inviter_user_id}, #{conn.quote(token)}, #{now}, #{now})
      RETURNING id
    SQL
  end

  # ---- answer_options.image_url ----

  test "answer_options has nullable image_url string" do
    col = columns("answer_options")["image_url"]
    assert_not_nil col, "answer_options.image_url is missing"
    assert_equal :string, col.type
    assert col.null, "answer_options.image_url must be nullable"
  end

  # ---- quiz_attempts.user_id / invitation_id ----

  test "quiz_attempts user_id is nullable with fk to users and index" do
    col = columns("quiz_attempts")["user_id"]
    assert_not_nil col, "quiz_attempts.user_id is missing"
    assert col.null, "quiz_attempts.user_id must be nullable (guest play)"

    fk = foreign_keys("quiz_attempts").find { |f| f.column == "user_id" }
    assert_not_nil fk, "FK quiz_attempts.user_id is missing"
    assert_equal "users", fk.to_table.to_s

    assert_includes index_names("quiz_attempts"), "index_quiz_attempts_on_user_id"
  end

  test "quiz_attempts invitation_id is nullable with fk to invitations and index" do
    col = columns("quiz_attempts")["invitation_id"]
    assert_not_nil col, "quiz_attempts.invitation_id is missing"
    assert col.null, "quiz_attempts.invitation_id must be nullable"

    fk = foreign_keys("quiz_attempts").find { |f| f.column == "invitation_id" }
    assert_not_nil fk, "FK quiz_attempts.invitation_id is missing"
    assert_equal "invitations", fk.to_table.to_s

    assert_includes index_names("quiz_attempts"), "index_quiz_attempts_on_invitation_id"
  end

  # ---- quizzes.generation_metadata ----

  test "quizzes has generation_metadata jsonb defaulting to empty object" do
    col = columns("quizzes")["generation_metadata"]
    assert_not_nil col, "quizzes.generation_metadata is missing"
    assert_equal :jsonb, col.type
    assert_jsonb_empty_default(col, "quizzes.generation_metadata")
  end

  # ---- questions.question_type / payload ----

  test "questions has question_type defaulting to multiple_choice plus jsonb payload default" do
    type_col = columns("questions")["question_type"]
    assert_not_nil type_col, "questions.question_type is missing"
    assert_equal "multiple_choice", type_col.default

    payload_col = columns("questions")["payload"]
    assert_not_nil payload_col, "questions.payload is missing"
    assert_equal :jsonb, payload_col.type
    assert_jsonb_empty_default(payload_col, "questions.payload")
  end

  # ---- responses.text_answer / payload ----

  test "responses has nullable text_answer plus jsonb payload default" do
    text_col = columns("responses")["text_answer"]
    assert_not_nil text_col, "responses.text_answer is missing"
    assert_equal :text, text_col.type
    assert text_col.null, "responses.text_answer must be nullable"

    payload_col = columns("responses")["payload"]
    assert_not_nil payload_col, "responses.payload is missing"
    assert_equal :jsonb, payload_col.type
    assert_jsonb_empty_default(payload_col, "responses.payload")
  end

  # ---- invitations table ----

  test "invitations has quiz fk, inviter fk to users, and not-null unique token" do
    cols = columns("invitations")

    quiz_col = cols["quiz_id"]
    assert_not_nil quiz_col, "invitations.quiz_id is missing"
    assert_not quiz_col.null, "invitations.quiz_id must be not-null"

    inviter_col = cols["inviter_user_id"]
    assert_not_nil inviter_col, "invitations.inviter_user_id is missing"
    assert_not inviter_col.null, "invitations.inviter_user_id must be not-null"

    token_col = cols["token"]
    assert_not_nil token_col, "invitations.token is missing"
    assert_equal :string, token_col.type
    assert_not token_col.null, "invitations.token must be not-null"

    assert_not_nil cols["created_at"], "invitations must have created_at"

    quiz_fk = foreign_keys("invitations").find { |f| f.column == "quiz_id" }
    assert_not_nil quiz_fk, "FK invitations.quiz_id is missing"
    assert_equal "quizzes", quiz_fk.to_table.to_s

    inviter_fk = foreign_keys("invitations").find { |f| f.column == "inviter_user_id" }
    assert_not_nil inviter_fk, "FK invitations.inviter_user_id is missing"
    assert_equal "users", inviter_fk.to_table.to_s, "inviter FK must point at users"
  end

  test "invitations has unique index on token and on quiz plus inviter" do
    uniques = unique_index_names("invitations")
    assert_includes uniques, "index_invitations_on_token"
    assert_includes uniques, "index_invitations_on_quiz_id_and_inviter_user_id"
  end

  # ---- scoring_mode untouched / no minutes_played ----

  test "quizzes scoring_mode column is untouched" do
    assert_not_nil columns("quizzes")["scoring_mode"], "quizzes.scoring_mode must stay"
  end

  test "no minutes_played on quiz tables" do
    %w[answer_options quiz_attempts quizzes questions responses invitations].each do |table|
      assert_not_includes columns(table).keys, "minutes_played", "#{table} must not have minutes_played"
    end
  end

  test "schema.rb shows new columns and no minutes_played" do
    schema = File.read(Rails.root.join("db/schema.rb"))
    %w[image_url generation_metadata question_type payload text_answer invitations token inviter_user_id invitation_id].each do |col|
      assert_includes schema, %("#{col}"), "db/schema.rb must mention #{col}"
    end
    assert_not_includes schema, "minutes_played", "db/schema.rb must not mention minutes_played"
  end

  # ---- functional edge cases ----

  test "guest attempt with nil user_id still saves" do
    attempt = QuizAttempt.create!(quiz: q1_quiz("Q1 Guest Quiz"))
    assert_nil attempt.user_id
    assert_nil attempt.invitation_id
  end

  test "attempt linked to user and invitation saves" do
    user = q1_user("q1-player@example.com")
    quiz = q1_quiz("Q1 Invite Quiz")
    row = q1_invitation_row(quiz_id: quiz.id, inviter_user_id: user.id, token: "q1-token-1")
    invitation_id = row.first["id"]

    attempt = QuizAttempt.create!(quiz: quiz, user_id: user.id, invitation_id: invitation_id)
    assert_equal user.id, attempt.user_id
    assert_equal invitation_id, attempt.invitation_id
  end

  test "duplicate invitation token is rejected" do
    user = q1_user("q1-dup@example.com")
    quiz = q1_quiz("Q1 Dup Quiz")
    q1_invitation_row(quiz_id: quiz.id, inviter_user_id: user.id, token: "q1-dup-token")
    other_quiz = q1_quiz("Q1 Dup Quiz 2")
    assert_raises(ActiveRecord::RecordNotUnique) do
      q1_invitation_row(quiz_id: other_quiz.id, inviter_user_id: user.id, token: "q1-dup-token")
    end
  end

  test "second invitation for same quiz and inviter is rejected" do
    user = q1_user("q1-stable@example.com")
    quiz = q1_quiz("Q1 Stable Quiz")
    q1_invitation_row(quiz_id: quiz.id, inviter_user_id: user.id, token: "q1-stable-a")
    assert_raises(ActiveRecord::RecordNotUnique) do
      q1_invitation_row(quiz_id: quiz.id, inviter_user_id: user.id, token: "q1-stable-b")
    end
  end

  test "attempt with unknown user_id is rejected by fk" do
    quiz = q1_quiz("Q1 FK Quiz")
    assert_raises(ActiveRecord::InvalidForeignKey) do
      QuizAttempt.create!(quiz: quiz, user_id: 9_999_999_999)
    end
  end

  test "new question defaults question_type and payload" do
    quiz = q1_quiz("Q1 Defaults Quiz")
    question = quiz.questions.create!(
      text: "Q1 default question?",
      answer_options_attributes: [
        { text: "Yes", is_correct: true },
        { text: "No", is_correct: false }
      ]
    )
    question.reload
    assert_equal "multiple_choice", question.question_type
    assert_equal({}, question.payload)
  end

  test "new quiz defaults generation_metadata to empty object" do
    quiz = q1_quiz("Q1 Metadata Quiz")
    assert_equal({}, quiz.reload.generation_metadata)
  end

  test "response text_answer stays nil unless set and payload defaults" do
    quiz = q1_quiz("Q1 Response Quiz")
    question = quiz.questions.create!(
      text: "Q1 response question?",
      answer_options_attributes: [
        { text: "A", is_correct: true },
        { text: "B", is_correct: false }
      ]
    )
    attempt = QuizAttempt.create!(quiz: quiz)
    response = attempt.responses.create!(question: question)
    response.reload
    assert_nil response.text_answer
    assert_equal({}, response.payload)
  end
end

# frozen_string_literal: true

require "test_helper"

# Q11 — Leaderboard (named only, score then time) + share-sheet/copy UI.
#
# Done when (from quiz-tickets.md Q11):
#   - seeded quiz with 2 named + 1 guest shows only the 2 named ordered by
#     score then faster time; guests excluded even via invite.
#   - leaderboard page linked from saved-quiz results, viewable signed-out.
#   - signing in later never backfills guest attempts to a user (no claim).
#   - desktop without navigator.share copies + confirms; mobile with share
#     opens native (asserted on the Stimulus controller source: share() ->
#     clipboard.writeText + Copied -> readonly manual-copy input).
class LeaderboardShareTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @carol = User.create!(email_address: "carol@example.com", password: "password123")
    @quiz = Quiz.create!(title: "Q11 Board Quiz", scoring_mode: "partial_credit")
    @q1 = @quiz.questions.create!(
      text: "Q11 first?", points: 1000, order_index: 0,
      answer_options_attributes: [
        { text: "Right A", is_correct: true, color: "red", order_index: 0 },
        { text: "Wrong A", is_correct: false, color: "blue", order_index: 1 }
      ]
    )
    @q2 = @quiz.questions.create!(
      text: "Q11 second?", points: 1000, order_index: 1,
      answer_options_attributes: [
        { text: "Wrong B", is_correct: false, color: "red", order_index: 0 },
        { text: "Right B", is_correct: true, color: "blue", order_index: 1 }
      ]
    )
    @invitation = Invitation.stable_for(@quiz, @alice)
  end

  test "board shows only named ordered by score then faster; guest excluded" do
    alice = finish_all_correct(@alice, duration: 20.seconds)
    bob = finish_all_correct(@bob, duration: 200.seconds)
    assert_equal alice.total_score, bob.total_score, "setup: scores must tie so duration decides"
    carol = finish_one_of_two(@carol)
    assert carol.total_score < alice.total_score, "setup: carol must trail on score"
    guest = guest_finish_all_correct
    assert_nil guest.user_id

    get leaderboard_quiz_path(@quiz)
    assert_response :success
    %w[one two carol].each do |handle|
      assert_includes response.body, handle, "named player #{handle} must appear"
    end
    assert_select "tbody tr", { count: 3 }, "only the 3 named attempts; guest excluded"
    alice_i = response.body.index("one")
    bob_i = response.body.index("two")
    carol_i = response.body.index("carol")
    assert alice_i < bob_i, "tied score: faster (alice) ranks above slower (bob)"
    assert bob_i < carol_i, "higher score ranks above lower score"
    assert_includes response.body, "#{alice.total_score} points"
    assert_includes response.body, "2 of 2 correct"
    assert_includes response.body, "1 of 2 correct"
  end

  test "unfinished named attempts stay off the board" do
    finish_all_correct(@alice, duration: 20.seconds)
    @quiz.quiz_attempts.create!(user: @bob, started_at: Time.current)
    get leaderboard_quiz_path(@quiz)
    assert_response :success
    assert_select "tbody tr", { count: 1 }
    assert_includes response.body, "one"
    assert_not_includes response.body, "two"
  end

  test "guest opens leaderboard while logged out" do
    finish_all_correct(@alice, duration: 20.seconds)
    guest_finish_all_correct
    sign_out
    get leaderboard_quiz_path(@quiz)
    assert_response :success
    assert_includes response.body, "Leaderboard"
    assert_select "tbody tr", { count: 1 }, "guest sees the board but stays off it"
  end

  test "saved-quiz results link the public board and carry the share sheet" do
    sign_in_as(@alice)
    attempt = finish_all_correct(@alice, duration: 20.seconds)
    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, leaderboard_quiz_path(@quiz),
      "results must link the public leaderboard page"
    assert_includes response.body, 'data-controller="share"'
    assert_includes response.body, 'id="share"'
    assert_includes response.body, 'id="leaderboard"'
    # Same absolute link as Q9 in all paths.
    assert_match(%r{data-share-url-value="http://[^"]+/i/[^"]+"}, response.body,
      "share value must be the absolute invite URL")
    assert_includes response.body, invite_url(@invitation.token)
  end

  test "guest results show no share sheet or send affordance" do
    guest = guest_finish_all_correct
    get results_quiz_attempt_path(guest)
    assert_response :success
    assert_not_includes response.body, 'data-controller="share"'
    assert_not_includes response.body, "Share this quiz"
    assert_includes response.body, leaderboard_quiz_path(@quiz),
      "guests can still reach the public board"
  end

  test "signing in later never backfills guest attempts; no claim UI" do
    guest = guest_finish_all_correct
    token = guest.invitation.token
    sign_in_as(@bob)
    get results_quiz_attempt_path(guest)
    assert_response :success
    assert_nil guest.reload.user_id, "guest row must stay user_id nil after sign-in"
    assert_no_match(/claim/i, response.body, "no claim path may be offered")
    get leaderboard_quiz_path(@quiz)
    assert_response :success
    assert_nil guest.reload.user_id
    assert_no_match(/claim/i, response.body)
    assert_select "tbody tr", { count: 0 }, "guest row never lands on the board"
    # The invite link itself still works for the signed-in user (new attempt).
    get invite_path(token)
    assert_response :redirect
    assert_equal @bob.id, Invitation.find_by!(token: token).quiz_attempts.order(:created_at).last.user_id
    assert_nil guest.reload.user_id, "opening the link mints a new row; the old guest row is untouched"
  end

  test "share controller: native sheet, AbortError silent, clipboard Copied, manual fallback" do
    source = File.read(Rails.root.join("app/javascript/controllers/share_controller.js"))
    assert_includes source, "navigator.share", "mobile path opens the native sheet"
    assert_includes source, "AbortError", "cancelling the sheet is silent"
    assert_includes source, "navigator.clipboard.writeText", "desktop path copies the link"
    assert_includes source, "Copied", "desktop copy shows confirmation"
    assert_includes source, "readonly", "last resort reveals a readonly input with the raw URL"
    assert_includes source, "static values", "url (absolute _url), title, text come from values"
  end

  test "leaderboard path never reads generation_metadata to rebuild questions" do
    # Write-only contract (same shape as the Q9 invite-open assertion):
    # the board path plays stored rows. Mentions are allowed only as
    # write-only comments + the save-time store helper in
    # quizzes_controller; nothing may index into it or trigger generation.
    readers = %w[
      app/controllers/quizzes_controller.rb
      app/models/quiz_attempt.rb
      app/views/quizzes/leaderboard.html.erb
      app/views/quiz_attempts/results.html.erb
    ].select do |file|
      File.read(Rails.root.join(file)).include?("generation_metadata")
    end
    assert_empty readers - %w[app/controllers/quizzes_controller.rb],
      "generation_metadata must never be read on the board path"
    board_source = File.read(Rails.root.join("app/controllers/quizzes_controller.rb"))
    assert_no_match(/generation_metadata\[/, board_source,
      "leaderboard must not index into generation_metadata")
    assert_not_includes board_source, "QuizGenerator",
      "leaderboard must never trigger generation"
  end

  private

  def correct_id(question)
    question.answer_options.correct.first.id
  end

  def wrong_id(question)
    question.answer_options.where(is_correct: false).first.id
  end

  def paint(question, answer_id)
    { question_id: question.id, selected_answer_ids: [ answer_id ], time_taken_ms: 500 }
  end

  # Named player answers everything correctly, then the wall-clock duration
  # is pinned so ordering tests are deterministic.
  def finish_all_correct(user, duration:)
    attempt = @quiz.quiz_attempts.create!(user: user, started_at: duration.ago)
    attempt.submit_response(paint(@q1, correct_id(@q1)))
    attempt.submit_response(paint(@q2, correct_id(@q2)))
    start = duration.ago
    attempt.update_columns(started_at: start, completed_at: start + duration)
    attempt.reload
  end

  def finish_one_of_two(user)
    attempt = @quiz.quiz_attempts.create!(user: user, started_at: 2.minutes.ago)
    attempt.submit_response(paint(@q1, correct_id(@q1)))
    attempt.submit_response(paint(@q2, wrong_id(@q2)))
    attempt.reload
  end

  def guest_finish_all_correct
    get invite_path(@invitation.token)
    attempt = @invitation.quiz_attempts.order(:created_at).last
    post quiz_attempt_responses_path(attempt), params: { response: paint(@q1, correct_id(@q1)) }
    post quiz_attempt_responses_path(attempt), params: { response: paint(@q2, correct_id(@q2)) }
    attempt.reload
  end
end

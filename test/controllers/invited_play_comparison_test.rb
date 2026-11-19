# frozen_string_literal: true

require "test_helper"

# Q10 — Invitation play (guest allowed) + inviter-best comparison.
#
# Done when (from quiz-tickets.md Q10):
#   - QuizAttemptsController#create accepts invitation_token: guest persists
#     with user_id nil but invitation_id set.
#   - Results for an invited attempt render side-by-side friend score/count
#     + inviter best score/count (best = inviter's best finished attempt on
#     the quiz, score DESC then faster wall-clock duration ASC); winner
#     callout (higher wins, score tie → faster wins).
#   - Inviter never played → friend score/count alone, no placeholder and no
#     check-back copy.
#   - Invited flow keeps Q6 snap / Q7 clock / Q8 endings style (score + count,
#     no breakdown).
class InvitedPlayComparisonTest < ActionDispatch::IntegrationTest
  setup do
    @inviter = users(:one)
    @quiz = Quiz.create!(title: "Q10 Invite Play", scoring_mode: "partial_credit")
    @q1 = @quiz.questions.create!(
      text: "Q10 first question?", points: 1000, order_index: 0,
      answer_options_attributes: [
        { text: "Right A", is_correct: true, color: "red", order_index: 0 },
        { text: "Wrong A", is_correct: false, color: "blue", order_index: 1 }
      ]
    )
    @q2 = @quiz.questions.create!(
      text: "Q10 second question?", points: 1000, order_index: 1,
      answer_options_attributes: [
        { text: "Wrong B", is_correct: false, color: "red", order_index: 0 },
        { text: "Right B", is_correct: true, color: "blue", order_index: 1 }
      ]
    )
    @invitation = Invitation.stable_for(@quiz, @inviter)
  end

  test "guest creates with invitation_token: user_id nil, invitation set" do
    post quiz_attempts_path, params: { invitation_token: @invitation.token }
    assert_response :redirect
    attempt = @invitation.quiz_attempts.order(:created_at).last
    assert_redirected_to quiz_attempt_path(attempt)
    assert_nil attempt.user_id, "guest attempt keeps user_id nil"
    assert_equal @invitation.id, attempt.invitation_id
    assert_equal @quiz.id, attempt.quiz_id
  end

  test "signed-in friend creates with invitation_token: user + invitation set" do
    friend = users(:two)
    sign_in_as(friend)
    post quiz_attempts_path, params: { invitation_token: @invitation.token }
    assert_response :redirect
    attempt = @invitation.quiz_attempts.order(:created_at).last
    assert_equal friend.id, attempt.user_id
    assert_equal @invitation.id, attempt.invitation_id
  end

  test "guest create without token stays signed-in only" do
    assert_no_difference("QuizAttempt.count") do
      post quiz_attempts_path, params: { quiz_id: @quiz.id }
    end
    assert_redirected_to new_session_path
  end

  test "unknown invitation_token raises not found" do
    post quiz_attempts_path, params: { invitation_token: "no-such-token" }
    assert_response :not_found
  end

  test "guest completes invite link: row stored, results score+count, no breakdown" do
    attempt = guest_finish_all_correct

    assert_nil attempt.reload.user_id
    assert_equal @invitation.id, attempt.invitation_id
    assert_not_nil attempt.completed_at

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "#{attempt.total_score} points"
    assert_includes response.body, "2 of 2 correct"
    assert_not_includes response.body, "Q10 first question?",
      "Q8 endings style: no per-question breakdown on invited results"
    assert_not_includes response.body, "Inviter",
      "inviter never played: no placeholder, no empty state, no check-back"
    assert_not_includes response.body, "check back"
    assert_not_includes response.body, "You vs Inviter"
    assert_not_includes response.body, "You win!"
    assert_not_includes response.body, "Inviter wins!"
  end

  test "invited show uses shared play shell: tiles + countdown (Q6/Q7 path)" do
    get invite_path(@invitation.token)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "play-tiles"
    assert_includes response.body, "play-countdown"
  end

  test "inviter best present and higher: both scores + inviter wins" do
    inviter_finish_all_correct
    attempt = guest_finish_one_of_two

    get results_quiz_attempt_path(attempt)
    assert_response :success
    # Side-by-side: friend score/count + inviter best score/count.
    assert_includes response.body, "You vs Inviter"
    assert_includes response.body, "Your score"
    assert_includes response.body, "Inviter's best"
    assert_includes response.body, "#{attempt.reload.total_score} points"
    assert_includes response.body, "#{@inviter_best.total_score} points"
    assert_includes response.body, "🏆 Inviter wins!"
    assert_not_includes response.body, "🎉 You win!"
  end

  test "friend outscores inviter best: you win" do
    inviter_finish_one_of_two
    attempt = guest_finish_all_correct

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "You vs Inviter"
    assert_includes response.body, "🎉 You win!"
    assert_not_includes response.body, "🏆 Inviter wins!"
  end

  test "score tie goes to faster wall-clock duration, not time_taken sum" do
    # Both answer identically (same time_taken_ms → same score); the only
    # difference is wall-clock duration. Friend is faster → friend wins.
    inviter_finish_all_correct
    slow_start = 5.minutes.ago
    @inviter_best.update_columns(started_at: slow_start, completed_at: slow_start + 200.seconds)

    attempt = guest_finish_all_correct
    assert_equal @inviter_best.total_score, attempt.reload.total_score,
      "setup: scores must tie so duration decides"
    fast_start = 1.minute.ago
    attempt.update_columns(started_at: fast_start, completed_at: fast_start + 20.seconds)

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "🎉 You win!",
      "tied score must break on faster completed_at - started_at"
  end

  test "slower tied friend loses to inviter best" do
    inviter_finish_all_correct
    fast_start = 1.minute.ago
    @inviter_best.update_columns(started_at: fast_start, completed_at: fast_start + 20.seconds)

    attempt = guest_finish_all_correct
    assert_equal @inviter_best.total_score, attempt.reload.total_score
    slow_start = 5.minutes.ago
    attempt.update_columns(started_at: slow_start, completed_at: slow_start + 200.seconds)

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "🏆 Inviter wins!"
  end

  test "best of several inviter attempts is compared (highest score)" do
    inviter_finish_one_of_two
    low = @inviter_best.total_score
    inviter_finish_all_correct
    high = @inviter_best.total_score
    assert high > low, "setup: second inviter attempt must score higher"

    attempt = guest_finish_one_of_two

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "#{high} points",
      "comparison must use the inviter's best finished attempt"
    assert_includes response.body, "🏆 Inviter wins!"
  end

  test "non-invited results show no comparison block" do
    sign_in_as(@inviter)
    post quiz_attempts_path, params: { quiz_id: @quiz.id }
    attempt = @quiz.quiz_attempts.order(:created_at).last
    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q1.id,
                  selected_answer_ids: [ correct_id(@q1) ],
                  time_taken_ms: 500 }
    }
    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q2.id,
                  selected_answer_ids: [ correct_id(@q2) ],
                  time_taken_ms: 500 }
    }

    get results_quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "of 2 correct"
    assert_not_includes response.body, "You vs Inviter"
    assert_not_includes response.body, "Inviter's best"
  end

  test "guest cannot view non-invited results" do
    sign_in_as(@inviter)
    post quiz_attempts_path, params: { quiz_id: @quiz.id }
    attempt = @quiz.quiz_attempts.order(:created_at).last
    sign_out

    get results_quiz_attempt_path(attempt)
    assert_redirected_to new_session_path
  end

  private

  def correct_id(question)
    question.answer_options.correct.first.id
  end

  def wrong_id(question)
    question.answer_options.where(is_correct: false).first.id
  end

  # Full guest flow through the invite entry: open link, answer every
  # question correctly (fast), finishing the attempt. Returns the attempt.
  def guest_finish_all_correct
    get invite_path(@invitation.token)
    assert_response :redirect
    attempt = @invitation.quiz_attempts.order(:created_at).last
    assert_nil attempt.user_id

    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q1.id,
                  selected_answer_ids: [ correct_id(@q1) ],
                  time_taken_ms: 500 }
    }
    assert_response :redirect
    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q2.id,
                  selected_answer_ids: [ correct_id(@q2) ],
                  time_taken_ms: 500 }
    }
    assert_response :redirect
    attempt.reload
  end

  # Guest answers first correctly, second wrongly. Returns the attempt.
  def guest_finish_one_of_two
    get invite_path(@invitation.token)
    attempt = @invitation.quiz_attempts.order(:created_at).last

    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q1.id,
                  selected_answer_ids: [ correct_id(@q1) ],
                  time_taken_ms: 500 }
    }
    post quiz_attempt_responses_path(attempt), params: {
      response: { question_id: @q2.id,
                  selected_answer_ids: [ wrong_id(@q2) ],
                  time_taken_ms: 500 }
    }
    attempt.reload
  end

  def inviter_finish_all_correct
    @inviter_best = @quiz.quiz_attempts.create!(user: @inviter, started_at: 2.minutes.ago)
    @inviter_best.submit_response(
      question_id: @q1.id, selected_answer_ids: [ correct_id(@q1) ], time_taken_ms: 500
    )
    @inviter_best.submit_response(
      question_id: @q2.id, selected_answer_ids: [ correct_id(@q2) ], time_taken_ms: 500
    )
    @inviter_best.reload
  end

  def inviter_finish_one_of_two
    @inviter_best = @quiz.quiz_attempts.create!(user: @inviter, started_at: 2.minutes.ago)
    @inviter_best.submit_response(
      question_id: @q1.id, selected_answer_ids: [ correct_id(@q1) ], time_taken_ms: 500
    )
    @inviter_best.submit_response(
      question_id: @q2.id, selected_answer_ids: [ wrong_id(@q2) ], time_taken_ms: 500
    )
    @inviter_best.reload
  end
end

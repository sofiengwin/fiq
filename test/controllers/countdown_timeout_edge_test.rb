# frozen_string_literal: true

require "test_helper"

# Q7 checker edge cases: timeout must win over a "late but correct" payload.
# A correct selection that arrives at/after the limit (or with an explicit
# timeout flag) scores 0 through the snap path — never as a late correct
# answer. Written from the ticket, not from the implementation.
class PlayCountdownTimeoutEdgeTest < ActionController::TestCase
  tests PlayController

  setup do
    @play_session = PlaySession.create!(
      session_id: "q7-edge-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Which club?",
          "correct_answer" => [ 11 ],
          "points" => 1000,
          "time_limit_seconds" => 7,
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea" }
          ],
          "players" => []
        }
      ],
      started_at: Time.current
    )
    session[:play_session_id] = @play_session.id
  end

  test "late correct selection at the limit still scores 0 as a timeout" do
    post :answer,
      params: { selected_ids: [ "11" ], question_index: "0", time_taken_ms: 7_000 },
      format: :turbo_stream
    assert_response :success

    @play_session.reload
    last = @play_session.responses.last
    assert_equal 0, last["points"], "late correct must score 0, not base points"
    assert_not last["is_correct"]
    assert_equal 0, @play_session.total_score
    assert_equal 1, @play_session.current_index, "timeout still advances"
  end

  test "explicit timeout flag zeroes a fast correct selection" do
    post :answer,
      params: { selected_ids: [ "11" ], question_index: "0",
                time_taken_ms: 100, timeout: "1" },
      format: :turbo_stream
    assert_response :success

    @play_session.reload
    last = @play_session.responses.last
    assert_equal 0, last["points"]
    assert_not last["is_correct"]
  end
end

# Q7 checker edge case on the saved-attempt path: a correct selection posted
# with full-limit elapsed ms goes through submit_timeout (zero + snap).
class SavedAttemptCountdownTimeoutEdgeTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q7 Edge", scoring_mode: "partial_credit")
    @question = @quiz.questions.create!(
      text: "Which club?", points: 1000, time_limit_seconds: 7,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1 }
      ]
    )
  end

  test "late correct selection on a saved attempt scores 0" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
    correct_id = @question.answer_options.correct.first.id

    post quiz_attempt_responses_path(attempt),
      params: { response: { question_id: @question.id,
                            selected_answer_ids: [ correct_id ],
                            time_taken_ms: 7_000 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    persisted = attempt.reload.responses.find_by(question_id: @question.id)
    assert_equal 0, persisted.score_awarded,
      "late correct must score 0 via the timeout path"
    assert_empty persisted.selected_answer_ids,
      "timeout stores an empty selection, not the late pick"
  end
end

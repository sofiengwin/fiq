# frozen_string_literal: true

require "test_helper"
require_relative "../test_helpers/shared_play_screen_assertions"

# Q5: single-tap locks + submits with no submit/Confirm/Next control;
# multi toggles until Confirm; server scores exact match and ignores
# double submits. Badge wording stays "Select all that apply".
class PlayLockSingleTest < ActionController::TestCase
  tests PlayController

  setup do
    @play_session = PlaySession.create!(
      session_id: "q5-single-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Which club?",
          "correct_answer" => [ 11 ],
          "points" => 1000,
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea" },
            { "id" => 33, "name" => "Liverpool" },
            { "id" => 44, "name" => "Man City" }
          ],
          "players" => []
        },
        {
          "type" => "club_alumni",
          "prompt" => "Which club again?",
          "correct_answer" => [ 22 ],
          "points" => 1000,
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea" },
            { "id" => 33, "name" => "Liverpool" },
            { "id" => 44, "name" => "Man City" }
          ],
          "players" => []
        }
      ],
      started_at: Time.current
    )
    session[:play_session_id] = @play_session.id
  end

  test "single mode renders no submit/Confirm/Next and no badge" do
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    assert_nil doc.at_css("#play-multi-badge"),
      "single-correct must not show the multi badge"
    assert_empty doc.css("#play-submit"),
      "single mode must render no submit/Confirm control"
    assert_empty doc.css("a, button").select { |el| el.text.strip =~ /\A(Next|Confirm|Submit)\b/i },
      "single mode must render no Next/Confirm/Submit control"

    form = doc.at_css("form#play-form")
    assert_equal "1", form["data-answer-selection-correct-count-value"]
    assert_includes form["data-action"].to_s, "submit->answer-selection#guard"
    assert doc.at_css("#play-question-index"), "expected stale-submit token field"
    assert_equal "0", doc.at_css("#play-question-index")["value"]
    assert_not_empty doc.css("#play-tiles input[data-action='change->answer-selection#toggle']"),
      "tiles must toggle through the lock controller"
  end

  test "double POST with a stale question_index answers only once" do
    post :answer, params: { selected_ids: [ "11" ], question_index: "0" }
    assert_redirected_to play_question_path
    @play_session.reload
    assert_equal 1, @play_session.current_index
    assert_equal 1, @play_session.responses.length
    assert @play_session.responses.first["is_correct"]

    post :answer, params: { selected_ids: [ "22" ], question_index: "0" }
    assert_redirected_to play_question_path
    @play_session.reload
    assert_equal 1, @play_session.current_index,
      "stale double-submit must be ignored, not scored as the next question"
    assert_equal 1, @play_session.responses.length
  end

  test "client correct_count hint never affects server scoring" do
    post :answer, params: { selected_ids: [ "22" ], question_index: "0", correct_count: "99" }
    @play_session.reload
    assert_equal 1, @play_session.responses.length
    assert_not @play_session.responses.first["is_correct"],
      "wrong pick stays wrong even with a tampered correct_count param"
    assert_equal 0, @play_session.responses.first["points"]
  end
end

# Q5 multi mode on the /play path: badge + disabled Confirm, partial
# exact-match scoring through QuizScoring.
class PlayLockMultiTest < ActionController::TestCase
  tests PlayController
  include SharedPlayScreenAssertions

  setup do
    @play_session = PlaySession.create!(
      session_id: "q5-multi-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Pick both clubs",
          "correct_answer" => [ 11, 22 ],
          "points" => 1000,
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea" },
            { "id" => 33, "name" => "Liverpool" },
            { "id" => 44, "name" => "Man City" }
          ],
          "players" => []
        }
      ],
      started_at: Time.current
    )
    session[:play_session_id] = @play_session.id
  end

  test "multi mode shows badge and a disabled Confirm, no Next" do
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    badge = doc.at_css("#play-multi-badge")
    assert badge, "multi must show the badge"
    assert_equal "Select all that apply", badge.text.strip

    confirm = doc.at_css("#play-submit")
    assert confirm, "multi must render the Confirm button"
    assert_equal "Confirm", confirm["value"]
    assert confirm["disabled"], "Confirm starts disabled until a tile is picked"

    form = doc.at_css("form#play-form")
    assert_equal "2", form["data-answer-selection-correct-count-value"]
    assert_equal confirm["id"], form.at_css("[data-answer-selection-target='submit']")["id"]
    assert_empty doc.css("a, button").select { |el| el.text.strip =~ /\ANext\b/i },
      "no Next button anywhere in the play loop"
  end

  test "partial multi selection scores exact-or-zero" do
    post :answer, params: { selected_ids: [ "11" ], question_index: "0" }
    @play_session.reload
    assert_equal 1, @play_session.responses.length
    assert_not @play_session.responses.first["is_correct"],
      "partial multi-select must score zero (exact match only)"
    assert_equal 0, @play_session.responses.first["points"]
    assert_equal 0, @play_session.streak
  end
end

# Q5 on the saved-attempt path: same shell contract + idempotent submit.
class QuizAttemptLockTest < ActionDispatch::IntegrationTest
  include SharedPlayScreenAssertions

  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q5 Lock", scoring_mode: "partial_credit")
    @single = @quiz.questions.create!(
      text: "Which club?", points: 1000,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 }
      ]
    )
    @multi = @quiz.questions.create!(
      text: "Pick both", points: 1000,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: true, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 }
      ]
    )
  end

  test "single attempt renders lock shell with no submit and no badge" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
    get quiz_attempt_path(attempt)
    assert_response :success

    assert_shared_play_screen(response.body,
      question_number: 1,
      total_questions: 2,
      score: 0,
      streak: 0,
      effective_limit: QuizScoring::DEFAULT_LIMIT_SECONDS,
      tile_count: 4,
      prompt_image_src: nil,
      form_action: quiz_attempt_responses_path(attempt),
      input_name: "response[selected_answer_ids][]")

    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_nil doc.at_css("#play-multi-badge")
    form = doc.at_css("form#play-form")
    assert_equal "1", form["data-answer-selection-correct-count-value"]
  end

  test "multi attempt shows badge and disabled Confirm" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
    attempt.submit_response(
      { question_id: @single.id,
        selected_answer_ids: [ @single.answer_options.correct.first.id ],
        time_taken_ms: 500 })
    get quiz_attempt_path(attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    assert_equal "Select all that apply",
      doc.at_css("#play-multi-badge").text.strip
    confirm = doc.at_css("#play-submit")
    assert confirm, "multi must render Confirm"
    assert_equal "Confirm", confirm["value"]
    assert confirm["disabled"], "Confirm starts disabled"
    form = doc.at_css("form#play-form")
    assert_equal "2", form["data-answer-selection-correct-count-value"]
  end

  test "double submit of the same question is idempotent" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
    correct_id = @single.answer_options.correct.first.id
    params = { response: { question_id: @single.id,
      selected_answer_ids: [ correct_id ], time_taken_ms: 500 } }

    assert_difference("Response.count", 1) do
      post quiz_attempt_responses_path(attempt), params: params
    end
    assert_no_difference("Response.count") do
      post quiz_attempt_responses_path(attempt), params: params
    end
    assert_equal 1, attempt.reload.responses.where(question_id: @single.id).count
  end
end

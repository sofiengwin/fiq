# frozen_string_literal: true

require "test_helper"
require_relative "../test_helpers/shared_play_screen_assertions"

# Q3: saved quiz_attempt_path renders the same shared play screen shell
# as /play/question (same selectors/ids), including Turbo-frame requests.
class QuizAttemptSharedScreenTest < ActionDispatch::IntegrationTest
  include SharedPlayScreenAssertions

  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q3 Quiz", scoring_mode: "partial_credit", time_limit_seconds: nil)
    @question = @quiz.questions.create!(
      text: "Which club?",
      image_url: "https://example.com/badge.png",
      time_limit_seconds: 7,
      points: 1000,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 },
        { text: "Spurs", is_correct: false, color: "red", order_index: 4 },
        { text: "Everton", is_correct: false, color: "blue", order_index: 5 }
      ]
    )
    @attempt = @quiz.quiz_attempts.create!(user_id: @user.id, started_at: Time.current, total_score: 0, streak: 0)
  end

  test "show renders shared shell identical to play screen contract" do
    get quiz_attempt_path(@attempt)
    assert_response :success

    assert_shared_play_screen(response.body,
      question_number: 1,
      total_questions: 1,
      score: 0,
      streak: 0,
      effective_limit: 7,
      tile_count: 6,
      prompt_image_src: "https://example.com/badge.png",
      form_action: quiz_attempt_responses_path(@attempt),
      input_name: "response[selected_answer_ids][]")
  end

  test "show via turbo-frame renders the same shared shell" do
    get quiz_attempt_path(@attempt), headers: { "Turbo-Frame" => "question-frame" }
    assert_response :success

    assert_shared_play_screen(response.body,
      question_number: 1,
      total_questions: 1,
      score: 0,
      streak: 0,
      effective_limit: 7,
      tile_count: 6,
      prompt_image_src: "https://example.com/badge.png",
      form_action: quiz_attempt_responses_path(@attempt),
      input_name: "response[selected_answer_ids][]")
  end

  test "question without its own limit falls back to 20s countdown slot" do
    @question.update!(time_limit_seconds: nil)
    get quiz_attempt_path(@attempt)
    assert_response :success

    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_equal "20", doc.at_css("#play-countdown").text.strip
  end

  test "streak renders only when greater than zero" do
    @attempt.update!(streak: 2, total_score: 1500)
    get quiz_attempt_path(@attempt)
    assert_response :success

    doc = Nokogiri::HTML::Document.parse(response.body)
    assert doc.at_css("#play-streak"), "expected streak badge when streak is 2"
    assert_equal "Score: 1500", doc.at_css("#play-score").text.strip
  end
end

# frozen_string_literal: true

require "test_helper"

# Q7: countdown (question || quiz || 20) + timeout as zero + snap.
#
# Header countdown starts at question.effective_time_limit; the quiz-timer
# ticks each second with CSS-only urgency (<=10s/<=5s) and records
# time_taken_ms for the Q2 speed bonus. On zero the timer auto-submits an
# empty/timeout selection once through the same Q6 snap path (correct
# shown, +0, header updates, auto-advance). Fast correct answers still
# earn strictly more than slow ones via the locked Q2 curve.
class PlayCountdownTimeoutTest < ActionController::TestCase
  tests PlayController

  setup do
    @play_session = PlaySession.create!(
      session_id: "q7-countdown-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Which club?",
          "correct_answer" => [ 11 ],
          "points" => 1000,
          "time_limit_seconds" => 7,
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

  test "countdown starts at the question limit (7), not the 20 default" do
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    assert_equal "7", doc.at_css("#play-countdown").text.strip
    screen = doc.at_css("#play-screen")
    assert_equal "quiz-timer", screen["data-controller"]
    assert_equal "7", screen["data-quiz-timer-seconds-value"]
  end

  test "countdown falls back to 20 when the question carries no limit" do
    @play_session.update!(current_index: 1)
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    assert_equal "20", doc.at_css("#play-countdown").text.strip
    assert_equal "20",
      doc.at_css("#play-screen")["data-quiz-timer-seconds-value"]
  end

  test "timer owns the tick targets, hidden time field, and urgency hooks" do
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    assert_equal "display",
      doc.at_css("#play-countdown")["data-quiz-timer-target"]
    time_field = doc.at_css("#play-time-taken")
    assert time_field, "expected #play-time-taken hidden field"
    assert_equal "timeTaken", time_field["data-quiz-timer-target"]

    form = doc.at_css("form#play-form")
    assert_equal "form", form["data-quiz-timer-target"]

    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    assert_match(/#play-countdown\.is-low/, css,
      "expected <=10s urgency styling owned by CSS")
    assert_match(/#play-countdown\.is-critical/, css,
      "expected <=5s urgency styling owned by CSS")
  end

  test "timeout submit awards 0, snaps, and advances exactly once" do
    post :answer,
      params: { selected_ids: [], question_index: "0", time_taken_ms: 7_000 },
      format: :turbo_stream
    assert_response :success

    @play_session.reload
    assert_equal 1, @play_session.responses.length
    last = @play_session.responses.last
    assert_equal [], last["selected"]
    assert_not last["is_correct"]
    assert_equal 0, last["points"]
    assert_equal 0, @play_session.total_score
    assert_equal 0, @play_session.streak
    assert_equal 1, @play_session.current_index

    snap = snap_doc(response.body, "play-screen")
    tiles = snap.css("#play-tiles .play-tile")
    assert_includes tiles.find { |t| t["data-answer-id"] == "11" }["class"].split,
      "is-correct", "timeout snap must still show the correct tile"
    assert_empty snap.css("#play-tiles .is-wrong-pick"),
      "empty timeout picks nothing, so nothing flashes"
    assert_equal 0, snap_points(snap)
    assert_equal "Score: 0", snap.at_css("#play-score").text.strip
    assert_empty snap.css("form"), "snap must remove interactivity"
    advance = snap.at_css("[data-controller='snap-advance']")
    assert advance, "timeout snap must auto-advance"
    assert advance["data-snap-advance-delay-value"].to_i.between?(1200, 1800)
    assert_equal play_question_path, advance["data-snap-advance-url-value"]

    # The timer fires once: a late duplicate of the same question is ignored.
    post :answer,
      params: { selected_ids: [], question_index: "0", time_taken_ms: 7_000 },
      format: :turbo_stream
    @play_session.reload
    assert_equal 1, @play_session.responses.length,
      "timeout must submit once; the stale duplicate is ignored"
    assert_equal 1, @play_session.current_index
  end

  test "fast correct answers earn strictly more than slow ones" do
    fast_session = PlaySession.create!(
      session_id: "q7-fast",
      questions: @play_session.questions,
      started_at: Time.current
    )
    slow_session = PlaySession.create!(
      session_id: "q7-slow",
      questions: @play_session.questions,
      started_at: Time.current
    )

    fast_session.process_answer!([ 11 ], time_taken_ms: 500,
      effective_limit_ms: 7_000)
    slow_session.process_answer!([ 11 ], time_taken_ms: 6_500,
      effective_limit_ms: 7_000)

    assert_operator fast_session.total_score, :>, slow_session.total_score,
      "the Q2 speed curve must reward the faster correct answer"
  end

  private

  def snap_doc(body, target)
    doc = Nokogiri::HTML::Document.parse(body)
    stream = doc.css("turbo-stream").find { |s| s["target"] == target }
    assert stream, "expected a turbo-stream replacing #{target}"
    Nokogiri::HTML::Document.parse(stream.at_css("template")&.inner_html.to_s)
  end

  def snap_points(snap)
    el = snap.at_css("#snap-points")
    assert el, "expected #snap-points near the tiles"
    el.text[/\+(\d+)/, 1].to_i
  end
end

# Q7 on the saved-attempt path: countdown from effective_time_limit
# (question || quiz || 20), timeout via submit_timeout scoring zero with
# the Q6 snap, submitted exactly once.
class SavedAttemptCountdownTimeoutTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q7 Countdown", scoring_mode: "partial_credit",
                         time_limit_seconds: 45)
    @timed = @quiz.questions.create!(
      text: "Which club?", points: 1000, time_limit_seconds: 7,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 }
      ]
    )
    @untimed = @quiz.questions.create!(
      text: "Which other club?", points: 1000, order_index: 1,
      answer_options_attributes: [
        { text: "Spurs", is_correct: false, color: "red", order_index: 0 },
        { text: "Everton", is_correct: true, color: "blue", order_index: 1 }
      ]
    )
  end

  test "countdown starts at the question limit, falls back to quiz then 20" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
    get quiz_attempt_path(attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_equal "7", doc.at_css("#play-countdown").text.strip
    assert_equal "7",
      doc.at_css("#play-screen")["data-quiz-timer-seconds-value"]

    @timed.update!(time_limit_seconds: nil)
    get quiz_attempt_path(attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_equal "45", doc.at_css("#play-countdown").text.strip,
      "question without a limit falls back to the quiz limit"

    @quiz.update!(time_limit_seconds: nil)
    get quiz_attempt_path(attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_equal "20", doc.at_css("#play-countdown").text.strip,
      "nil question and quiz limits count down from 20"
  end

  test "timeout posts once, awards 0, and snaps with auto-advance" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 2)
    correct_id = @timed.answer_options.correct.first.id

    assert_difference("Response.count", 1) do
      post quiz_attempt_responses_path(attempt),
        params: { response: { question_id: @timed.id,
                              selected_answer_ids: [],
                              time_taken_ms: 7_000 } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success

    persisted = attempt.reload.responses.find_by(question_id: @timed.id)
    assert_equal 0, persisted.score_awarded
    assert_equal 0, attempt.streak
    assert_empty persisted.selected_answer_ids

    snap = snap_doc(response.body, "question-frame")
    tiles = snap.css("#play-tiles .play-tile")
    assert_includes tiles.find { |t| t["data-answer-id"] == correct_id.to_s }["class"].split,
      "is-correct", "timeout snap must still show the correct tile"
    assert_empty snap.css("#play-tiles .is-wrong-pick")
    assert_equal 0, snap_points(snap)
    assert_equal "Score: 0", snap.at_css("#play-score").text.strip
    advance = snap.at_css("[data-controller='snap-advance']")
    assert advance, "timeout snap must auto-advance"
    assert advance["data-snap-advance-delay-value"].to_i.between?(1200, 1800)
    assert_equal quiz_attempt_path(attempt),
      advance["data-snap-advance-url-value"]

    # The zero timer fires once: re-posting the same question is ignored.
    assert_no_difference("Response.count") do
      post quiz_attempt_responses_path(attempt),
        params: { response: { question_id: @timed.id,
                              selected_answer_ids: [],
                              time_taken_ms: 7_000 } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_equal 1,
      attempt.reload.responses.where(question_id: @timed.id).count
  end

  private

  def snap_doc(body, target)
    doc = Nokogiri::HTML::Document.parse(body)
    stream = doc.css("turbo-stream").find { |s| s["target"] == target }
    assert stream, "expected a turbo-stream replacing #{target}"
    Nokogiri::HTML::Document.parse(stream.at_css("template")&.inner_html.to_s)
  end

  def snap_points(snap)
    el = snap.at_css("#snap-points")
    assert el, "expected #snap-points near the tiles"
    el.text[/\+(\d+)/, 1].to_i
  end
end

# frozen_string_literal: true

require "test_helper"

# Q6: snap reveal + points + auto-advance on the saved-attempt path.
#
# Lock/confirm/timeout responses (Turbo Stream replacing question-frame)
# must: mark correct tile(s) .is-correct, flash wrongly tapped tile(s)
# .is-wrong-pick, render +N (or +0) near the tiles, update the header
# score/streak, remove interactivity (no form/inputs/links/buttons), and
# auto-navigate once via snap-advance (~1.5s) to the next question (or
# results when done). Shown +N must equal the persisted score_awarded
# from the Q2 QuizScoring formula.
class SavedAttemptSnapRevealTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q6 Snap", scoring_mode: "partial_credit")
    @single = @quiz.questions.create!(
      text: "Which club?", points: 1000,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 }
      ]
    )
    @second = @quiz.questions.create!(
      text: "Which other club?", points: 1000, order_index: 1,
      answer_options_attributes: [
        { text: "Spurs", is_correct: false, color: "red", order_index: 0 },
        { text: "Everton", is_correct: true, color: "blue", order_index: 1 },
        { text: "Leeds", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Villa", is_correct: false, color: "green", order_index: 3 }
      ]
    )
    @multi = @quiz.questions.create!(
      text: "Pick both", points: 1000, order_index: 2,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: true, color: "blue", order_index: 1 },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 }
      ]
    )
  end

  test "correct tap snaps: correct highlighted, +N>0 equals persisted, header updates, auto-advance, no Next" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id, started_at: Time.current)
    correct_id = @single.answer_options.correct.first.id

    post quiz_attempt_responses_path(attempt),
      params: { response: { question_id: @single.id, selected_answer_ids: [ correct_id ], time_taken_ms: 500 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    snap = snap_doc(response.body, "question-frame")
    tiles = snap.css("#play-tiles .play-tile")
    assert_equal 4, tiles.size, "snap must re-render every tile"

    correct_tile = tiles.find { |t| t["data-answer-id"] == correct_id.to_s }
    assert correct_tile, "snap must carry data-answer-id per tile"
    assert_includes correct_tile["class"].split, "is-correct"
    assert_empty snap.css("#play-tiles .is-wrong-pick"),
      "correct tap must flash nothing"

    shown = snap_points(snap)
    assert shown > 0, "correct tap must show +N>0"
    persisted = attempt.reload.responses.find_by(question_id: @single.id)
    assert_equal persisted.score_awarded, shown,
      "shown +N must equal the persisted QuizScoring award"
    assert_equal "Score: #{attempt.total_score}", snap.at_css("#play-score").text.strip
    assert_equal attempt.total_score, shown, "first-question header equals the award"

    assert_empty snap.css("form"), "snap must remove the form (no interactivity)"
    assert_empty snap.css("#play-tiles input"), "snap tiles must not be inputs"
    assert_empty snap.css("a, button").select { |el| el.text.strip =~ /\A(Next|Confirm|Submit|See Results)/i },
      "snap must render no Next/Confirm/Submit navigation"
    assert_equal 1, snap.css("[data-controller='snap-advance']").size,
      "exactly one auto-advance timer so it fires once"
    advance = snap.at_css("[data-controller='snap-advance']")
    assert advance["data-snap-advance-delay-value"].to_i.between?(1200, 1800),
      "auto-advance must fire after ~1.5s"
    assert_equal quiz_attempt_path(attempt), advance["data-snap-advance-url-value"]
    assert_equal "question-frame", advance["data-snap-advance-frame-value"]
  end

  test "wrong tap snaps: correct highlighted, pick flashes, +0 persisted" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id, started_at: Time.current)
    correct_id = @single.answer_options.correct.first.id
    wrong_id = @single.answer_options.where(is_correct: false).first.id

    post quiz_attempt_responses_path(attempt),
      params: { response: { question_id: @single.id, selected_answer_ids: [ wrong_id ], time_taken_ms: 500 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    snap = snap_doc(response.body, "question-frame")
    tiles = snap.css("#play-tiles .play-tile")
    correct_tile = tiles.find { |t| t["data-answer-id"] == correct_id.to_s }
    wrong_tile = tiles.find { |t| t["data-answer-id"] == wrong_id.to_s }
    assert_includes correct_tile["class"].split, "is-correct",
      "wrong tap must still highlight the correct tile"
    assert_includes wrong_tile["class"].split, "is-wrong-pick",
      "wrongly tapped tile must flash"
    assert_equal 0, snap_points(snap)
    assert_equal 0, attempt.reload.responses.find_by(question_id: @single.id).score_awarded
    assert_equal "Score: 0", snap.at_css("#play-score").text.strip
  end

  test "multi partial selection snaps as wrong with +0" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id, started_at: Time.current)
    one_correct = @multi.answer_options.correct.first.id

    post quiz_attempt_responses_path(attempt),
      params: { response: { question_id: @multi.id, selected_answer_ids: [ one_correct ], time_taken_ms: 500 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    snap = snap_doc(response.body, "question-frame")
    assert_equal 0, snap_points(snap), "partial multi-select must show +0"
    assert_equal 0, attempt.reload.responses.find_by(question_id: @multi.id).score_awarded
    assert_equal 2, snap.css("#play-tiles .play-tile.is-correct").size,
      "both correct tiles still highlight on a partial pick"
    assert_empty snap.css("#play-tiles .is-wrong-pick"),
      "a picked-but-correct tile must not flash as a wrong pick"
  end

  test "final question snap auto-advances to results with no Next link" do
    attempt = @quiz.quiz_attempts.create!(user_id: @user.id, started_at: Time.current)
    [ @single, @second ].each do |q|
      attempt.submit_response(
        question_id: q.id,
        selected_answer_ids: [ q.answer_options.correct.first.id ],
        time_taken_ms: 500)
    end

    post quiz_attempt_responses_path(attempt),
      params: { response: { question_id: @multi.id,
        selected_answer_ids: @multi.answer_options.correct.map(&:id), time_taken_ms: 500 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert attempt.reload.completed?, "last answer must complete the attempt"

    snap = snap_doc(response.body, "question-frame")
    advance = snap.at_css("[data-controller='snap-advance']")
    assert_equal results_quiz_attempt_path(attempt), advance["data-snap-advance-url-value"],
      "done snap must auto-navigate to results"
    assert_empty snap.css("a, button").select { |el| el.text.strip =~ /Next/i },
      "no Next Question link left over from Q5"
  end

  test "question_result views keep no Next Question links" do    body = File.read(Rails.root.join("app/views/quiz_attempts/_question_result.html.erb"))
    assert_no_match(/Next Question/, body, "_question_result must not link Next Question")
    refute File.exist?(Rails.root.join("app/views/quiz_attempts/_question_result.turbo_stream.erb")),
      "the turbo-stream variant was folded into the single snap partial (no divergent Next-link copy)"
    create_stream = File.read(Rails.root.join("app/views/responses/create.turbo_stream.erb"))
    assert_no_match(/Next Question/, create_stream, "create stream must not link Next Question")
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

# Q6 on the /play path: Turbo submissions get the snap reveal (correct
# highlighted + persisted +N, wrong pick flashes +0) with single-fire
# auto-advance; plain HTML posts keep the Q5 redirect fallback.
class PlaySnapRevealTest < ActionController::TestCase
  tests PlayController

  setup do
    @play_session = PlaySession.create!(
      session_id: "q6-snap-session",
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

  test "turbo correct answer snaps with persisted +N and advances to next question" do
    post :answer, params: { selected_ids: [ "11" ], question_index: "0", time_taken_ms: 500 },
      format: :turbo_stream
    assert_response :success

    snap = snap_doc(response.body, "play-screen")
    tiles = snap.css("#play-tiles .play-tile")
    assert_equal 4, tiles.size
    correct_tile = tiles.find { |t| t["data-answer-id"] == "11" }
    assert_includes correct_tile["class"].split, "is-correct"
    assert_empty snap.css("#play-tiles .is-wrong-pick")

    shown = snap_points(snap)
    assert shown > 0
    @play_session.reload
    assert_equal @play_session.responses.last["points"], shown,
      "shown +N must equal the persisted QuizScoring award"
    assert_equal "Score: #{@play_session.total_score}",
      snap.at_css("#play-score").text.strip

    assert_empty snap.css("form"), "snap must remove interactivity"
    assert_empty snap.css("a, button").select { |el| el.text.strip =~ /\A(Next|Confirm|Submit)/i }
    advance = snap.at_css("[data-controller='snap-advance']")
    assert advance, "expected the snap-advance timer"
    assert advance["data-snap-advance-delay-value"].to_i.between?(1200, 1800)
    assert_equal play_question_path, advance["data-snap-advance-url-value"]
  end

  test "turbo wrong answer snaps with flash and +0" do
    post :answer, params: { selected_ids: [ "22" ], question_index: "0", time_taken_ms: 500 },
      format: :turbo_stream
    assert_response :success

    snap = snap_doc(response.body, "play-screen")
    tiles = snap.css("#play-tiles .play-tile")
    assert_includes tiles.find { |t| t["data-answer-id"] == "11" }["class"].split, "is-correct"
    assert_includes tiles.find { |t| t["data-answer-id"] == "22" }["class"].split, "is-wrong-pick"
    assert_equal 0, snap_points(snap)
    assert_equal 0, @play_session.reload.responses.last["points"]
  end

  test "turbo final answer snaps toward results" do
    post :answer, params: { selected_ids: [ "11" ], question_index: "0", time_taken_ms: 500 },
      format: :turbo_stream
    post :answer, params: { selected_ids: [ "22" ], question_index: "1", time_taken_ms: 500 },
      format: :turbo_stream
    assert_response :success

    snap = snap_doc(response.body, "play-screen")
    assert_equal play_results_path, snap.at_css("[data-controller='snap-advance']")["data-snap-advance-url-value"]
  end

  test "html posts keep the redirect fallback" do
    post :answer, params: { selected_ids: [ "11" ], question_index: "0" }
    assert_redirected_to play_question_path
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

# Q6 static contract: wrong-pick flash exists but is disabled under
# reduced-motion (final colors + points still render); the auto-advance
# timer is a single setTimeout (~1.5s) guarded to fire once.
class SnapMotionContractTest < ActiveSupport::TestCase
  test "wrong-pick flash honors reduced motion" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    assert_match(/@keyframes snap-wrong-flash/, css, "expected a wrong-pick flash")
    assert_match(/\.play-tile\.is-wrong-pick\s*\{[^}]*animation:/, css)
    reduced = css[/@media \(prefers-reduced-motion: reduce\)(.|\n)*\z/m]
    assert reduced, "expected a reduced-motion block"
    assert_match(/is-wrong-pick[^}]*animation:\s*none/, reduced,
      "reduced motion must skip the flash animation")
  end

  test "snap-advance fires once after ~1.5s" do
    js = File.read(Rails.root.join("app/javascript/controllers/snap_advance_controller.js"))
    assert_equal 1, js.scan(/setTimeout/).size, "exactly one timer so it fires once"
    assert_match(/1500/, js, "default delay must be ~1.5s")
    assert_match(/advanced/, js, "must guard against repeat navigation")
  end
end

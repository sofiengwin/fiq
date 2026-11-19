# frozen_string_literal: true

require "test_helper"

# Q4: 6-option fixture renders the locked 4-pair cycle with matching shapes,
# answer images render with a label (never as a submit control alone),
# and no audio is emitted.
class PlayTilesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @quiz = Quiz.create!(title: "Q4 Tiles", scoring_mode: "partial_credit")
    @question = @quiz.questions.create!(
      text: "Which club?",
      points: 1000,
      answer_options_attributes: [
        { text: "Arsenal", is_correct: true, color: "red", order_index: 0 },
        { text: "Chelsea", is_correct: false, color: "blue", order_index: 1,
          image_url: "https://example.com/chelsea.png" },
        { text: "Liverpool", is_correct: false, color: "yellow", order_index: 2 },
        { text: "Man City", is_correct: false, color: "green", order_index: 3 },
        { text: "Spurs", is_correct: false, color: "orange", order_index: 4 },
        { text: "Everton", is_correct: false, color: "purple", order_index: 5 }
      ]
    )
    @attempt = @quiz.quiz_attempts.create!(user_id: @user.id,
      started_at: Time.current, total_score: 0, streak: 0)
  end

  test "six options render locked color cycle with matching shapes and sr labels" do
    get quiz_attempt_path(@attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    tiles = doc.css("#play-tiles > label .play-tile")
    assert_equal 6, tiles.length
    assert_equal %w[red blue yellow green red blue],
      tiles.map { |t| t["data-tile-color"] }

    shapes = tiles.map { |t| t.at_css("span[aria-hidden='true']")&.text&.strip }
    assert_equal %w[▲ ◆ ● ■ ▲ ◆], shapes

    sr_labels = tiles.map { |t| t.at_css("span.sr-only")&.text&.strip }
    assert_equal ["red-triangle:", "blue-diamond:", "yellow-circle:",
      "green-square:", "red-triangle:", "blue-diamond:"], sr_labels
  end

  test "answer image renders with label under it and alt text, never as its own control" do
    get quiz_attempt_path(@attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    tiles = doc.css("#play-tiles > label .play-tile")
    image_tile = tiles[1]
    img = image_tile.at_css("img.play-answer-image")
    assert img, "expected answer image in second tile"
    assert_equal "https://example.com/chelsea.png", img["src"]
    assert_equal "Chelsea", img["alt"], "image alt must be the answer text"
    label = image_tile.at_css(".play-answer-label")
    assert label, "expected label under the answer image"
    assert_equal "Chelsea", label.text.strip
    assert img.xpath("following-sibling::*").any?,
      "label must render under the image, not instead of it"
    assert img.ancestors("button, a, input").empty?,
      "answer image must never be a submit control by itself"
    assert_equal 0, doc.css("img.play-answer-image").size - 1

    text_tile = tiles[0]
    assert_nil text_tile.at_css("img"), "text-only tile must stay image-free"
    assert_includes text_tile.text, "Arsenal"
  end

  test "rendered play screen has no audio element" do
    get quiz_attempt_path(@attempt)
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)
    assert_empty doc.css("audio"), "no audio elements in play"
    assert_no_match(/<audio/i, response.body)
  end
end

# Q4: PlaySession hash-question branch renders the same locked cycle and
# supports per-option answer images.
class PlayTilesSessionTest < ActionController::TestCase
  tests PlayController

  setup do
    @play_session = PlaySession.create!(
      session_id: "q4-tiles-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Which club did ALL of these players play for?",
          "correct_answer" => [ 11 ],
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea", "image_url" => "https://example.com/chelsea.png" },
            { "id" => 33, "name" => "Liverpool" },
            { "id" => 44, "name" => "Man City" },
            { "id" => 55, "name" => "Spurs" },
            { "id" => 66, "name" => "Everton" }
          ],
          "players" => []
        }
      ],
      started_at: Time.current
    )
    session[:play_session_id] = @play_session.id
  end

  test "hash options render position-based cycle with image tile" do
    get :question
    assert_response :success
    doc = Nokogiri::HTML::Document.parse(response.body)

    tiles = doc.css("#play-tiles > label .play-tile")
    assert_equal 6, tiles.length
    assert_equal %w[red blue yellow green red blue],
      tiles.map { |t| t["data-tile-color"] }

    img = tiles[1].at_css("img.play-answer-image")
    assert img, "expected hash-option answer image"
    assert_equal "Chelsea", img["alt"]
    assert_equal "Chelsea", tiles[1].at_css(".play-answer-label").text.strip
  end
end

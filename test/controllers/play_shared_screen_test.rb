# frozen_string_literal: true

require "test_helper"
require_relative "../test_helpers/shared_play_screen_assertions"

# Q3: /play/question renders the shared play screen shell.
class PlaySharedScreenTest < ActionController::TestCase
  tests PlayController
  include SharedPlayScreenAssertions

  setup do
    @play_session = PlaySession.create!(
      session_id: "q3-play-session",
      questions: [
        {
          "type" => "club_alumni",
          "prompt" => "Which club did ALL of these players play for?",
          "correct_answer" => [ 11 ],
          "answer_hint" => nil,
          "options" => [
            { "id" => 11, "name" => "Arsenal" },
            { "id" => 22, "name" => "Chelsea" },
            { "id" => 33, "name" => "Liverpool" },
            { "id" => 44, "name" => "Man City" }
          ],
          "players" => [ { "id" => 1, "name" => "Player One" } ]
        }
      ],
      started_at: Time.current
    )
    session[:play_session_id] = @play_session.id
  end

  test "question renders shared shell with 2-col tiles and quit" do
    get :question
    assert_response :success

    assert_shared_play_screen(response.body,
      question_number: 1,
      total_questions: 1,
      score: 0,
      streak: 0,
      effective_limit: QuizScoring::DEFAULT_LIMIT_SECONDS,
      tile_count: 4,
      prompt_image_src: nil,
      form_action: play_answer_path,
      input_name: "selected_ids[]")
  end

  test "streak renders only when greater than zero" do
    @play_session.update!(streak: 3, total_score: 2500)
    get :question
    assert_response :success

    doc = Nokogiri::HTML::Document.parse(response.body)
    assert doc.at_css("#play-streak"), "expected streak badge when streak is 3"
  end
end

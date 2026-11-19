# frozen_string_literal: true

require "test_helper"

# Q12 — generation record-only + phase-2 schema shells + no-friends guardrails.
#
# Done when (from quiz-tickets.md Q12):
#   - Saving a quiz writes metadata with prompt/model/seed.
#   - grep shows generation_metadata read only on the save path
#     (quizzes/invitations controllers, write-only), never on the
#     invite/leaderboard/retake/play paths to build questions.
#   - questions.question_type/payload and responses.text_answer/payload are
#     writable at model level but unread in the play screen/scorer (tiles
#     come from answer_options + is_correct + image_url only); a
#     question_type=fill_blank question still renders tiles (or is at least
#     excluded) without crashing.
#   - No friends tables/routes; errata stays out of the pipeline (no
#     errata tables/routes/models, no re-fetch).
class Q12GenerationRecordOnlyTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @quiz = Quiz.create!(title: "Q12 Quiz", scoring_mode: "partial_credit")
    @question = @quiz.questions.create!(
      text: "Q12 question?", points: 1000, order_index: 0,
      answer_options_attributes: [
        { text: "Right", is_correct: true, color: "red", order_index: 0 },
        { text: "Wrong", is_correct: false, color: "blue", order_index: 1 }
      ]
    )
  end

  test "saving writes metadata with prompt, model and seed (create + update)" do
    sign_in_as(@user)
    post quizzes_path, params: {
      quiz: { title: "Q12 Meta" },
      generation_metadata: { nl_prompt: "q12 prompt", llm_model: "q12-model", seed: "q12-seed" }
    }
    quiz = Quiz.find_by!(title: "Q12 Meta")
    assert_equal "q12 prompt", quiz.generation_metadata["nl_prompt"]
    assert_equal "q12-model", quiz.generation_metadata["llm_model"]
    assert_equal "q12-seed", quiz.generation_metadata["seed"]

    patch quiz_path(quiz), params: {
      quiz: { title: "Q12 Meta" },
      generation_metadata: { nl_prompt: "q12 prompt 2", llm_model: "q12-model-2", seed: "q12-seed-2" }
    }
    assert_response :redirect
    assert_equal "q12 prompt 2", quiz.reload.generation_metadata["nl_prompt"]
    assert_equal "q12-model-2", quiz.generation_metadata["llm_model"]
    assert_equal "q12-seed-2", quiz.generation_metadata["seed"]
  end

  test "invite, leaderboard, retake and play paths never read the record to build questions" do
    # Zero mentions at all on the open/play paths.
    strict = %w[
      app/controllers/play_controller.rb
      app/controllers/quiz_attempts_controller.rb
      app/controllers/responses_controller.rb
      app/models/quiz_attempt.rb
      app/models/question.rb
      app/models/response.rb
      app/services/score_calculator.rb
      app/services/quiz_scoring.rb
      app/views/shared/_play_screen.html.erb
      app/views/shared/_play_snap.html.erb
      app/views/quiz_attempts/_question.html.erb
      app/views/quiz_attempts/_question_result.html.erb
      app/views/quiz_attempts/show.html.erb
      app/views/quiz_attempts/results.html.erb
      app/views/quizzes/leaderboard.html.erb
      app/views/responses/create.turbo_stream.erb
    ]
    readers = strict.select do |file|
      File.read(Rails.root.join(file)).include?("generation_metadata")
    end
    assert_empty readers,
      "generation_metadata must never appear on the invite/leaderboard/retake/play paths"

    # Write-side files: stored on save, never indexed back to rebuild.
    %w[
      app/controllers/quizzes_controller.rb
      app/controllers/invitations_controller.rb
    ].each do |file|
      source = File.read(Rails.root.join(file))
      assert_no_match(/generation_metadata\[/, source,
        "#{file} must not read the record back to build questions")
    end

    # Invite/leaderboard/retake never trigger generation.
    %w[
      app/controllers/invitations_controller.rb
      app/controllers/quiz_attempts_controller.rb
      app/controllers/responses_controller.rb
    ].each do |file|
      assert_not_includes File.read(Rails.root.join(file)), "QuizGenerator",
        "#{file} must never trigger generation on the open path"
    end
  end

  test "invite open plays stored questions even when the record is set" do
    @quiz.update!(generation_metadata: { "nl_prompt" => "p", "llm_model" => "m", "seed" => "s" })
    invitation = Invitation.stable_for(@quiz, @user)

    get invite_path(invitation.token)
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Q12 question?",
      "invite open must play stored questions, never rebuild from the record"
  end

  test "retake replays stored rows without rebuilding questions" do
    @quiz.update!(generation_metadata: { "nl_prompt" => "p", "llm_model" => "m", "seed" => "s" })
    sign_in_as(@user)

    post quiz_attempts_path, params: { quiz_id: @quiz.id }
    first = @quiz.quiz_attempts.order(:created_at).last
    post quiz_attempt_responses_path(first), params: {
      response: { question_id: @question.id,
                  selected_answer_ids: [ correct_id ],
                  time_taken_ms: 500 }
    }
    assert first.reload.completed?, "setup: single-question attempt must finish"

    # The Retake button on results posts here (no token): a fresh attempt on
    # the same stored quiz.
    assert_difference("@quiz.quiz_attempts.count", 1) do
      post quiz_attempts_path, params: { quiz_id: @quiz.id }
    end
    second = @quiz.quiz_attempts.order(:created_at).last
    assert_not_equal first.id, second.id

    get quiz_attempt_path(second)
    assert_response :success
    assert_includes response.body, "Q12 question?"
    assert_includes response.body, "play-tiles"
  end

  test "phase-2 shells are writable at model level" do
    @question.update!(question_type: "fill_blank", payload: { "answer" => "Right" })
    assert_equal "fill_blank", @question.reload.question_type
    assert_equal({ "answer" => "Right" }, @question.payload)

    attempt = @quiz.quiz_attempts.create!(user: @user, started_at: 1.minute.ago)
    response = attempt.submit_response(
      question_id: @question.id,
      selected_answer_ids: [ correct_id ],
      time_taken_ms: 500
    )
    response.update!(text_answer: "Right", payload: { "method" => "typed" })
    assert_equal "Right", response.reload.text_answer
    assert_equal({ "method" => "typed" }, response.payload)
  end

  test "play screen and scorer never read phase-2 fields" do
    files = %w[
      app/controllers/play_controller.rb
      app/controllers/quiz_attempts_controller.rb
      app/controllers/responses_controller.rb
      app/models/quiz_attempt.rb
      app/services/score_calculator.rb
      app/services/quiz_scoring.rb
      app/views/shared/_play_screen.html.erb
      app/views/shared/_play_snap.html.erb
      app/views/quiz_attempts/_question_result.html.erb
      app/views/responses/create.turbo_stream.erb
    ]
    readers = files.select do |file|
      code_lines(Rails.root.join(file)).any? do |line|
        line.match?(/question_type|text_answer|\.payload|payload\[|payload\.fetch|\["payload"\]|'payload'/)
      end
    end
    assert_empty readers,
      "play/scorer must read only answer_options + is_correct + image_url"
  end

  test "fill_blank question still renders tiles from answer_options without crashing" do
    @question.update!(question_type: "fill_blank", payload: { "answer" => "Right" })
    sign_in_as(@user)

    post quiz_attempts_path, params: { quiz_id: @quiz.id }
    attempt = @quiz.quiz_attempts.order(:created_at).last

    get quiz_attempt_path(attempt)
    assert_response :success
    assert_includes response.body, "play-tiles"
    assert_includes response.body, "Right"
    assert_includes response.body, "Wrong"
  end

  test "scorer grades fill_blank from answer_options only" do
    @question.update!(question_type: "fill_blank", payload: { "answer" => "Right" })

    exact = ScoreCalculator.new(
      question: @question,
      selected_answer_ids: [ correct_id ],
      time_taken_ms: 500,
      current_streak: 0
    ).calculate
    assert exact.correct?
    assert exact.final_score > 0

    wrong = ScoreCalculator.new(
      question: @question,
      selected_answer_ids: [ wrong_id ],
      time_taken_ms: 500,
      current_streak: 0
    ).calculate
    assert_not wrong.correct?
    assert_equal 0, wrong.final_score
  end

  test "no friends graph tables, routes or models; no errata pipeline" do
    schema = File.read(Rails.root.join("db/schema.rb"))
    assert_no_match(/create_table "(friends|friendships|challenges|invite_lists|errata|review_queue)"/, schema,
      "friends graph and errata pipeline stay deferred — no tables")

    routes = File.read(Rails.root.join("config/routes.rb"))
    assert_no_match(/friend|challenge|invite_list|errata/i, routes,
      "no friends/invite-list/challenge/errata routes")

    assert_empty Dir[Rails.root.join("app/models/{friend*,challenge*,errata*}")],
      "no friends/challenge/errata models"
    assert_empty Dir[Rails.root.join("db/migrate/*{friend*,challenge*,errata*}")],
      "no friends/challenge/errata migrations"
  end

  private

  def correct_id
    @question.answer_options.correct.first.id
  end

  def wrong_id
    @question.answer_options.where(is_correct: false).first.id
  end

  # Source lines minus comments, so Q12 guardrail notes may name the fields
  # they forbid without tripping the "never read" assertions. ERB comments
  # (<%# %>) are removed wholesale; Ruby full-line # comments are skipped.
  def code_lines(path)
    source = File.read(path)
    source = source.gsub(/<%#.*?%>/m, "") if path.to_s.end_with?(".erb")
    source.each_line.reject { |line| line.strip.start_with?("#") }
  end
end

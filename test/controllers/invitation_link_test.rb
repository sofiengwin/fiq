# frozen_string_literal: true

require "test_helper"

# Q9 — Stable invitation link + save-on-send + auth gates.
#
# Done when (from quiz-tickets.md Q9):
#   - signed-in creator mints twice → same URL
#   - opening link before inviter plays works
#   - unsaved-preview send persists quiz then returns link
#   - signed-out visitor sees no Share/Send button but can open /i/:token
#   - opening link always plays stored questions/answer_options, never
#     triggers generation (generation_metadata is write-only here)
class InvitationLinkTest < ActionDispatch::IntegrationTest
  setup do
    @inviter = users(:one)
    @quiz = Quiz.create!(title: "Q9 Invite Quiz", scoring_mode: "partial_credit")
    @question = @quiz.questions.create!(
      text: "Q9 stored question?",
      points: 1000,
      answer_options_attributes: [
        { text: "Stored A", is_correct: true, color: "red", order_index: 0 },
        { text: "Stored B", is_correct: false, color: "blue", order_index: 1 }
      ]
    )
  end

  test "signed-in mints twice and gets the same URL (one stable row)" do
    sign_in_as(@inviter)
    assert_difference("Invitation.count", 1) do
      post quiz_invitations_path(@quiz)
    end
    first_location = response.redirect_url
    assert_match(%r{/i/[^/]+$}, first_location)

    assert_no_difference("Invitation.count") do
      post quiz_invitations_path(@quiz)
    end
    assert_equal first_location, response.redirect_url,
      "second mint must return the same stable URL, not a new token"
  end

  test "signed-in player mints own link before ever playing" do
    sign_in_as(@inviter)
    assert_equal 0, QuizAttempt.where(quiz: @quiz).count
    post quiz_invitations_path(@quiz)
    assert_response :redirect
    invitation = Invitation.find_by!(quiz: @quiz, inviter_user_id: @inviter.id)
    assert_equal invite_url(invitation.token), response.redirect_url
  end

  test "guest opens link before inviter plays: new attempt, stored question" do
    sign_in_as(@inviter)
    post quiz_invitations_path(@quiz)
    token = Invitation.find_by!(quiz: @quiz, inviter_user_id: @inviter.id).token
    assert_equal 0, QuizAttempt.where(quiz: @quiz).count, "inviter has not played"
    sign_out

    get invite_path(token)
    assert_response :redirect
    attempt = Invitation.find_by!(token: token).quiz_attempts.order(:created_at).last
    assert_redirected_to quiz_attempt_path(attempt)
    assert_nil attempt.user_id, "guest attempt keeps user_id nil"
    assert_equal Invitation.find_by!(token: token).id, attempt.invitation_id

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Q9 stored question?"
    assert_includes response.body, "Stored A"
    assert_includes response.body, "Stored B"
  end

  test "guest can answer through an invited attempt with no login" do
    invitation = Invitation.stable_for(@quiz, @inviter)
    get invite_path(invitation.token)
    attempt = invitation.quiz_attempts.order(:created_at).last
    correct_id = @question.answer_options.correct.first.id

    assert_difference("Response.count", 1) do
      post quiz_attempt_responses_path(attempt), params: {
        response: { question_id: @question.id,
                    selected_answer_ids: [ correct_id ],
                    time_taken_ms: 500 }
      }
    end
    assert_nil attempt.reload.user_id
  end

  test "unsaved-preview send persists quiz (with metadata) then returns link" do
    sign_in_as(@inviter)
    post "/quizzes/preview/invitations", params: {
      quiz: {
        title: "Q9 Preview Quiz",
        description: "saved on send",
        questions_attributes: [
          { text: "Preview Q?",
            answer_options_attributes: [
              { text: "Yes", is_correct: true },
              { text: "No", is_correct: false }
            ] }
        ]
      },
      generation_metadata: { nl_prompt: "q9 prompt", llm_model: "q9-model", seed: "42" }
    }
    assert_response :redirect
    quiz = Quiz.find_by!(title: "Q9 Preview Quiz")
    assert_equal "saved on send", quiz.description
    assert_equal "q9 prompt", quiz.generation_metadata["nl_prompt"]
    assert_equal "q9-model", quiz.generation_metadata["llm_model"]
    assert_equal "42", quiz.generation_metadata["seed"]
    invitation = Invitation.find_by!(quiz: quiz, inviter_user_id: @inviter.id)
    assert_equal invite_url(invitation.token), response.redirect_url

    # The minted link opens the just-saved stored questions as a guest.
    sign_out
    get invite_path(invitation.token)
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Preview Q?"
  end

  test "quiz create stores generation_metadata write-only" do
    sign_in_as(@inviter)
    post quizzes_path, params: {
      quiz: { title: "Q9 Meta Quiz" },
      generation_metadata: { nl_prompt: "meta prompt", llm_model: "m", seed: "7" }
    }
    quiz = Quiz.find_by!(title: "Q9 Meta Quiz")
    assert_equal "meta prompt", quiz.generation_metadata["nl_prompt"]
  end

  test "signed-out sees no Share but can open the link; signed-in sees Share" do
    invitation = Invitation.stable_for(@quiz, @inviter)

    get quiz_path(@quiz)
    assert_response :success
    assert_not_includes response.body, "Share",
      "guests must see no send affordance"

    get invite_path(invitation.token)
    assert_response :redirect, "guests can still open /i/:token"

    sign_in_as(@inviter)
    get quiz_path(@quiz)
    assert_response :success
    assert_includes response.body, "Share"
  end

  test "minting requires sign-in" do
    post quiz_invitations_path(@quiz)
    assert_redirected_to new_session_path
    assert_equal 0, Invitation.where(quiz: @quiz).count
  end

  test "unknown token raises not found" do
    get invite_path("no-such-token")
    assert_response :not_found
  end

  test "invite open never reads generation_metadata to regenerate" do
    # Write-only contract: the open path plays stored rows. No reader of
    # generation_metadata may exist in the invite/play controllers or the
    # views they render, and the invite flow never calls the generator.
    readers = %w[
      app/controllers/invitations_controller.rb
      app/controllers/quiz_attempts_controller.rb
      app/controllers/responses_controller.rb
      app/models/quiz_attempt.rb
    ].select do |file|
      File.read(Rails.root.join(file)).include?("generation_metadata")
    end
    # invitations_controller mentions it only in write-only comments +
    # the store helper; quiz_attempts/responses/attempt must not at all.
    assert_empty readers - %w[app/controllers/invitations_controller.rb],
      "generation_metadata must never be read on the open path"
    invite_source = File.read(Rails.root.join("app/controllers/invitations_controller.rb"))
    assert_no_match(/generation_metadata\[/, invite_source,
      "invite open must not index into generation_metadata")
    assert_not_includes invite_source, "QuizGenerator",
      "invite open must never trigger generation"
  end
end

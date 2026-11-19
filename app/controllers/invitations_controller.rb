# frozen_string_literal: true

# Q9 — Stable invitation links + save-on-send.
#
# POST /quizzes/:quiz_id/invitations (signed-in only via the default
# require_authentication gate) creates-or-returns the caller's stable link.
# If :quiz_id is not a persisted id (e.g. "preview" from an unsaved NL
# preview/draft), the quiz is saved first — including its generation
# metadata — and then the link is minted.
#
# GET /i/:token is guest-accessible (no login): it opens the invitation's
# STORED questions/answer_options as a new attempt. generation_metadata is
# write-only — it is stored on save and NEVER read here to regenerate
# questions (see also the regression test asserting no reader exists on
# this path).
class InvitationsController < ApplicationController
  allow_unauthenticated_access only: %i[show]

  # Signed-in only: mint (or return) the caller's stable link for a quiz.
  def create
    @quiz = find_or_persist_quiz
    @invitation = Invitation.stable_for(@quiz, Current.user)
    redirect_to invite_url(@invitation.token)
  end

  # Guest allowed: open the stored quiz as a new attempt. Works before the
  # inviter has ever played — no finished attempt is required. The attempt
  # carries user_id nil for guests (Current.user is nil without a session)
  # and always points at the persisted invitation.
  def show
    @invitation = Invitation.find_by!(token: params[:token])
    # Resume the session from the cookie when present so a signed-in
    # opener is linked to the attempt; guests stay nil (no redirect).
    authenticated?
    # NOTE: play stored questions/answer_options only. Never read
    # quizzes.generation_metadata here to regenerate questions — it is a
    # write-only record of how the quiz was created.
    @attempt = @invitation.quiz.quiz_attempts.create!(
      user: Current.user,
      invitation: @invitation,
      started_at: Time.current
    )
    redirect_to quiz_attempt_path(@attempt)
  end

  private

  # Persisted quiz id → find. Anything else (e.g. "preview") → save the
  # passed quiz payload first (save-on-send), then mint the link.
  def find_or_persist_quiz
    return Quiz.find(params[:quiz_id]) if params[:quiz_id] =~ /\A\d+\z/

    Quiz.create!(unsaved_quiz_params).tap do |quiz|
      store_generation_metadata(quiz)
    end
  end

  def unsaved_quiz_params
    params.require(:quiz).permit(
      :title, :description, :time_limit_seconds,
      questions_attributes: [
        :text, :image_url, :time_limit_seconds, :points, :order_index,
        answer_options_attributes: [ :text, :is_correct, :order_index, :color ]
      ]
    )
  end

  # generation_metadata is write-only: persist the NL prompt/model/seed on
  # save. Nothing on the play/invite/leaderboard path may read it back to
  # rebuild questions (guarded by test + the NOTE on #show above).
  def store_generation_metadata(quiz)
    metadata = params[:generation_metadata]&.permit(:nl_prompt, :llm_model, :seed)
    return if metadata.blank?

    quiz.update!(generation_metadata: metadata.to_h)
  end
end

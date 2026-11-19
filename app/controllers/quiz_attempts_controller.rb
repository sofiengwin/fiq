# frozen_string_literal: true

class QuizAttemptsController < ApplicationController
  # Q9: guests open invited attempts via /i/:token with no login (the invite
  # entry redirects here). Q10: guests also create invited attempts with an
  # invitation_token and view invited results for the friend-vs-inviter
  # comparison. Non-invited create/results still require sign-in (see the
  # guards in #create/#results).
  allow_unauthenticated_access only: %i[show create results]
  before_action :set_attempt, only: %i[show results]

  def show
    @current_question = @attempt.current_question
    @progress = @attempt.progress
    @effective_limit = @current_question&.effective_time_limit || QuizScoring::DEFAULT_LIMIT_SECONDS
  end

  def create
    # Q10: invitation play (guest allowed). With an invitation_token the
    # attempt is built on the invitation's quiz with user: Current.user
    # (nil for guests) and the invitation link, so a guest row persists
    # with user_id nil but invitation_id set.
    # Q12: retake (quiz_id, no token) replays the same stored rows — a
    # fresh attempt on the stored questions/answer_options. The creation
    # record is write-only on save and is never read back on this path.
    if params[:invitation_token].present?
      # Resume the session from the cookie when present so a signed-in
      # friend is linked; guests have no session and stay nil (no redirect).
      authenticated?
      @invitation = Invitation.find_by!(token: params[:invitation_token])
      @quiz = @invitation.quiz
      @attempt = @quiz.quiz_attempts.create!(
        user: Current.user,
        invitation: @invitation,
        started_at: Time.current
      )
      redirect_to quiz_attempt_path(@attempt)
    else
      # Non-invited creation stays signed-in only.
      return request_authentication unless authenticated?

      @quiz = Quiz.find(params[:quiz_id])
      @attempt = @quiz.quiz_attempts.create!(user: Current.user, started_at: Time.current)
      redirect_to quiz_attempt_path(@attempt)
    end
  end

  def results
    @results = @attempt.calculate_results
    # Q10: friend-vs-inviter comparison, invited attempts only. Best is the
    # inviter's best finished attempt on this quiz: highest total_score,
    # ties broken by faster wall-clock duration (completed_at - started_at,
    # locked tie-break shared with QuizAttempt.ranked — never a sum of
    # time_taken_ms). Uninvited results stay signed-in only.
    if @attempt.invitation.present?
      @inviter_best = QuizAttempt.where(quiz: @attempt.quiz, user: @attempt.invitation.inviter)
                                 .finished.ranked.first
      if @inviter_best
        @inviter_best_correct = @inviter_best.responses.count(&:correct?)
        @comparison_winner = comparison_winner(@attempt, @inviter_best)
      end
    else
      # Non-invited results stay signed-in only.
      request_authentication unless authenticated?
    end

    # Q11 share sheet: same stable link as Q9. The invited attempt already
    # carries its invitation; otherwise mint-or-return the viewer's own.
    # Guests (not authenticated) get no share affordance at all.
    if authenticated?
      @share_invitation = @attempt.invitation.presence ||
                          Invitation.stable_for(@attempt.quiz, Current.user)
      @share_url = invite_url(@share_invitation.token)
    end
  end

  private

  # Q10 winner callout: higher total_score wins; on a score tie the faster
  # wall-clock duration (completed_at - started_at) wins; fully tied → :tie.
  def comparison_winner(friend_attempt, inviter_best)
    return :friend if friend_attempt.total_score.to_i > inviter_best.total_score.to_i
    return :inviter if inviter_best.total_score.to_i > friend_attempt.total_score.to_i

    friend_duration = QuizScoring.duration_seconds(friend_attempt.started_at, friend_attempt.completed_at)
    best_duration = QuizScoring.duration_seconds(inviter_best.started_at, inviter_best.completed_at)
    return :tie if friend_duration.nil? || best_duration.nil?
    return :tie if friend_duration == best_duration

    friend_duration < best_duration ? :friend : :inviter
  end

  def set_attempt
    @attempt = QuizAttempt.includes(invitation: :inviter, quiz: { questions: :answer_options }).find(params[:id])
  end
end

# frozen_string_literal: true

class ResponsesController < ApplicationController
  # Q9: guests play invited attempts with no login, so answering must not
  # require a session (attempts carry user_id nil + invitation_id).
  allow_unauthenticated_access only: %i[create]

  def create
    @attempt = QuizAttempt.find(params[:quiz_attempt_id])
    # Q12: answers score the stored questions/answer_options via QuizAttempt
    # (QuizScoring exact match). The creation record is never read here.
    # Q7: on zero the timer auto-submits an empty selection with full-limit
    # elapsed ms. Score it as a timeout (zero) through the same Q6 snap
    # path as a lock — never as a late correct answer. Re-posts of the
    # same question stay idempotent via submit_response's existing check.
    if response_timed_out?
      @response = @attempt.submit_timeout(timeout_question_id)
    else
      @response = @attempt.submit_response(response_params)
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to quiz_attempt_path(@attempt) }
    end
  end

  private

  def response_params
    params.require(:response).permit(:question_id, :time_taken_ms, selected_answer_ids: [])
  end

  def timeout_question_id
    params.require(:response).require(:question_id)
  end

  def response_timed_out?
    return false unless params[:response]

    return true if params[:response][:timeout].to_s == "1" ||
                   params[:response][:timeout].to_s == "true"

    question = @attempt.quiz.questions.find_by(id: params[:response][:question_id])
    return false unless question

    params[:response][:time_taken_ms].to_i >= question.effective_time_limit.to_i * 1000
  end
end

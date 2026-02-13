# frozen_string_literal: true

class ResponsesController < ApplicationController
  def create
    @attempt = QuizAttempt.find(params[:quiz_attempt_id])
    @response = @attempt.submit_response(response_params)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to quiz_attempt_path(@attempt) }
    end
  end

  private

  def response_params
    params.require(:response).permit(:question_id, :time_taken_ms, selected_answer_ids: [])
  end
end

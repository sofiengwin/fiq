# frozen_string_literal: true

class QuizAttemptsController < ApplicationController
  before_action :set_attempt, only: %i[show results]

  def show
    @current_question = @attempt.current_question
    @progress = @attempt.progress
  end

  def create
    @quiz = Quiz.find(params[:quiz_id])
    @attempt = @quiz.quiz_attempts.create!(started_at: Time.current)
    redirect_to quiz_attempt_path(@attempt)
  end

  def results
    @results = @attempt.calculate_results
  end

  private

  def set_attempt
    @attempt = QuizAttempt.includes(quiz: { questions: :answer_options }).find(params[:id])
  end
end

# frozen_string_literal: true

class QuizzesController < ApplicationController
  before_action :set_quiz, only: %i[show edit update destroy duplicate]

  def index
    @quizzes = Quiz.search(params[:search])
                   .order(created_at: :desc)
  end

  def show
  end

  def new
    @quiz = Quiz.new
    # Build one question with answer options for the form
    question = @quiz.questions.build
    Question::COLORS.first(4).each_with_index do |color, index|
      question.answer_options.build(color: color, order_index: index)
    end
  end

  def create
    @quiz = Quiz.new(quiz_params)
    if @quiz.save
      redirect_to @quiz, notice: "Quiz created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @quiz.update(quiz_params)
      redirect_to @quiz, notice: "Quiz updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quiz.destroy
    redirect_to quizzes_path, notice: "Quiz deleted."
  end

  def duplicate
    @new_quiz = @quiz.duplicate
    redirect_to edit_quiz_path(@new_quiz), notice: "Quiz duplicated!"
  end

  private

  def set_quiz
    @quiz = Quiz.find(params[:id])
  end

  def quiz_params
    params.require(:quiz).permit(
      :title, :description, :time_limit_seconds, :scoring_mode,
      questions_attributes: [
        :id, :text, :image_url, :time_limit_seconds, :points, :order_index, :_destroy,
        answer_options_attributes: [ :id, :text, :is_correct, :order_index, :color, :_destroy ]
      ]
    )
  end
end

# frozen_string_literal: true

class QuestionsController < ApplicationController
  before_action :set_quiz
  before_action :set_question, only: %i[edit update destroy]

  def new
    @question = @quiz.questions.build
    Question::COLORS.first(4).each_with_index do |color, index|
      @question.answer_options.build(color: color, order_index: index)
    end
  end

  def create
    @question = @quiz.questions.build(question_params)
    @question.order_index = @quiz.questions.count

    if @question.save
      redirect_to edit_quiz_path(@quiz), notice: "Question added!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to edit_quiz_path(@quiz), notice: "Question updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @question.destroy
    redirect_to edit_quiz_path(@quiz), notice: "Question deleted."
  end

  private

  def set_quiz
    @quiz = Quiz.find(params[:quiz_id])
  end

  def set_question
    @question = @quiz.questions.find(params[:id])
  end

  def question_params
    params.require(:question).permit(
      :text, :image_url, :time_limit_seconds, :points, :order_index,
      answer_options_attributes: [ :id, :text, :is_correct, :order_index, :color, :_destroy ]
    )
  end
end

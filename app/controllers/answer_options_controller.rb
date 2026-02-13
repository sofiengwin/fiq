# frozen_string_literal: true

class AnswerOptionsController < ApplicationController
  before_action :set_quiz
  before_action :set_question
  before_action :set_answer_option, only: %i[edit update destroy]

  def new
    @answer_option = @question.answer_options.build
    @answer_option.order_index = @question.answer_options.count
  end

  def create
    @answer_option = @question.answer_options.build(answer_option_params)
    @answer_option.order_index ||= @question.answer_options.count

    if @answer_option.save
      redirect_to edit_quiz_question_path(@quiz, @question), notice: "Answer option added!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @answer_option.update(answer_option_params)
      redirect_to edit_quiz_question_path(@quiz, @question), notice: "Answer option updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @answer_option.destroy
    redirect_to edit_quiz_question_path(@quiz, @question), notice: "Answer option deleted."
  end

  private

  def set_quiz
    @quiz = Quiz.find(params[:quiz_id])
  end

  def set_question
    @question = @quiz.questions.find(params[:question_id])
  end

  def set_answer_option
    @answer_option = @question.answer_options.find(params[:id])
  end

  def answer_option_params
    params.require(:answer_option).permit(:text, :is_correct, :order_index, :color)
  end
end

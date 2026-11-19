# frozen_string_literal: true

class QuizzesController < ApplicationController
  allow_unauthenticated_access only: %i[index show leaderboard]
  before_action :set_quiz, only: %i[show edit update destroy duplicate leaderboard]

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
      # Q9: generation_metadata is write-only — stored on save, never read
      # to regenerate questions on open (see InvitationsController#show).
      store_generation_metadata(@quiz)
      redirect_to @quiz, notice: "Quiz created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @quiz.update(quiz_params)
      # Q9: generation_metadata is write-only — stored on save, never read
      # to regenerate questions on open (see InvitationsController#show).
      store_generation_metadata(@quiz)
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

  # Q11 — public per-quiz leaderboard, viewable logged-out. Named finished
  # attempts only (score DESC, faster wall-clock duration ASC); guests stay
  # off the list even when they played via an invite. generation_metadata is
  # write-only — stored on save, never read here to rebuild questions.
  def leaderboard
    @entries = @quiz.quiz_attempts.leaderboard.includes(:user, responses: :selected_answers)
    # Same link as Q9 in all paths: the viewer's own stable invitation.
    # Looked up only (no mint on GET — minting stays POST-only); signed-in
    # viewers without one yet get a POST Share button instead.
    if authenticated?
      @share_invitation = Invitation.find_by(quiz: @quiz, inviter: Current.user)
      @share_url = invite_url(@share_invitation.token) if @share_invitation
    end
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

  # Q9: generation_metadata is write-only — persist the NL prompt/model/seed
  # on save. Nothing on the play/invite/leaderboard path may read it back
  # to rebuild questions (guarded by test + InvitationsController#show NOTE).
  def store_generation_metadata(quiz)
    metadata = params[:generation_metadata]&.permit(:nl_prompt, :llm_model, :seed)
    return if metadata.blank?

    quiz.update!(generation_metadata: metadata.to_h)
  end
end

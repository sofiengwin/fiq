class QuizAttempt < ApplicationRecord
  # Associations
  belongs_to :quiz
  has_many :responses, dependent: :destroy

  # Defaults
  attribute :total_score, :integer, default: 0
  attribute :streak, :integer, default: 0

  # Callbacks
  before_create :set_started_at

  def current_question
    answered_question_ids = responses.pluck(:question_id)
    quiz.questions.where.not(id: answered_question_ids).order(:order_index).first
  end

  def completed?
    completed_at.present?
  end

  def progress
    total = quiz.questions.count
    answered = responses.count
    { answered: answered, total: total, percentage: total > 0 ? (answered.to_f / total * 100).round : 0 }
  end

  def submit_response(response_params)
    question = quiz.questions.find(response_params[:question_id])
    selected_answer_ids = response_params[:selected_answer_ids] || []
    time_taken_ms = response_params[:time_taken_ms].to_i

    # Calculate score
    result = ScoreCalculator.new(
      question: question,
      selected_answer_ids: selected_answer_ids,
      time_taken_ms: time_taken_ms,
      current_streak: streak
    ).calculate

    # Create response
    response = responses.create!(
      question: question,
      time_taken_ms: time_taken_ms,
      score_awarded: result.final_score,
      submitted_at: Time.current
    )

    # Create response answers
    selected_answer_ids.each do |answer_id|
      response.response_answers.create!(answer_option_id: answer_id)
    end

    # Update attempt totals
    update!(
      total_score: total_score + result.final_score,
      streak: result.new_streak,
      completed_at: current_question.nil? ? Time.current : nil
    )

    response
  end

  def calculate_results
    {
      total_score: total_score,
      responses: responses.includes(:question, :selected_answers).map do |response|
        {
          question: response.question,
          score: response.score_awarded,
          correct: response.correct?,
          selected_answers: response.selected_answers,
          correct_answers: response.question.answer_options.correct
        }
      end,
      max_possible_score: quiz.questions.sum(:points),
      percentage: calculate_percentage
    }
  end

  private

  def set_started_at
    self.started_at ||= Time.current
  end

  def calculate_percentage
    max = quiz.questions.sum(:points)
    return 0 if max.zero?

    (total_score.to_f / max * 100).round
  end
end

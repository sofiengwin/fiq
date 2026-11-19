class QuizAttempt < ApplicationRecord
  # Associations
  belongs_to :quiz
  # Q9: invited play links attempts to an invitation; guests play with
  # user_id nil (nullable FK from Q1), so both stay optional.
  belongs_to :user, optional: true
  belongs_to :invitation, optional: true
  has_many :responses, dependent: :destroy

  # Defaults
  attribute :total_score, :integer, default: 0
  attribute :streak, :integer, default: 0

  # Callbacks
  before_create :set_started_at

  # Finished attempts only (completed_at set).
  scope :finished, -> { where.not(completed_at: nil) }

  # Q11 public board: named finished attempts only, score desc then faster
  # wall-clock duration (completed_at - started_at, locked tie-break — never
  # a sum of time_taken_ms). Guests (user_id nil, even via invite) stay off
  # the list but can still view the page; signing in later never backfills a
  # guest row to a user (no claim path).
  scope :leaderboard, -> { where.not(user_id: nil).ranked }

  # Leaderboard order (locked): score desc, then faster wall-clock duration
  # asc. Duration is completed_at - started_at (Q2 tie-break); never a sum
  # of time_taken_ms.
  scope :ranked, -> {
    finished
      .order(total_score: :desc)
      .order(Arel.sql("(quiz_attempts.completed_at - quiz_attempts.started_at) ASC"))
  }

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
    # Q5 idempotency: a double-tap / double-submit replays the same
    # question. The first submit already stored a response for it, so the
    # second is ignored instead of creating a duplicate row.
    existing = responses.find_by(question_id: question.id)
    return existing if existing

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

  # Timeout scores zero through the same scorer: empty selection + full time.
  def submit_timeout(question_id)
    question = quiz.questions.find(question_id)
    submit_response(
      question_id: question.id,
      selected_answer_ids: [],
      time_taken_ms: question.effective_time_limit * 1000
    )
  end

  # Wall-clock duration in seconds (locked tie-break, shared with PlaySession).
  def duration_seconds
    QuizScoring.duration_seconds(started_at, completed_at)
  end

  # Q11 leaderboard "correct?" count: how many responses scored above zero
  # (Response#correct? is score > 0, which only exact-match answers earn).
  def correct_count
    responses.count(&:correct?)
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

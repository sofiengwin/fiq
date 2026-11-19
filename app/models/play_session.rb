# frozen_string_literal: true

class PlaySession < ApplicationRecord
  belongs_to :user, optional: true

  validates :session_id, presence: true

  scope :active, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }

  # Find or create an active game for the session
  def self.find_active_for(session_id)
    active.find_by(session_id: session_id)
  end

  def game_active?
    completed_at.nil? && current_index < questions.length
  end

  def game_complete?
    current_index >= questions.length
  end

  def current_question
    questions[current_index]
  end

  def progress
    {
      current: current_index + 1,
      total: questions.length,
      score: total_score,
      streak: streak
    }
  end

  def process_answer!(selected_ids, time_taken_ms: 0, effective_limit_ms: nil)
    question = current_question
    selected = Array(selected_ids).map(&:to_i).reject(&:zero?)
    scored = QuizScoring.score(
      correct_ids: question["correct_answer"],
      selected_ids: selected,
      base_points: question["points"] || QuizScoring::DEFAULT_BASE_POINTS,
      time_taken_ms: time_taken_ms,
      effective_limit_ms: effective_limit_ms || play_question_limit_ms(question),
      streak: streak
    )

    # Add response
    self.responses << {
      "question_index" => current_index,
      "selected" => selected,
      "correct_answer" => Array(question["correct_answer"]),
      "is_correct" => scored.correct?,
      "points" => scored.points
    }

    # Update game state
    self.total_score += scored.points
    self.streak = scored.new_streak
    self.current_index += 1

    # Mark complete if finished
    self.completed_at = Time.current if game_complete?

    save!
  end

  # Timeout scores zero through the same scorer: empty selection + full time.
  def process_timeout!(effective_limit_ms: nil)
    question = current_question
    limit_ms = effective_limit_ms || play_question_limit_ms(question)
    process_answer!([], time_taken_ms: limit_ms, effective_limit_ms: limit_ms)
  end

  def correct_count
    responses.count { |r| r["is_correct"] }
  end

  def percentage
    return 0 if questions.empty?
    (correct_count.to_f / questions.length * 100).round
  end

  # Get response with full question data for results display
  def responses_with_questions
    responses.map do |response|
      question = questions[response["question_index"]]
      response.merge(
        "prompt" => question["prompt"],
        "answer_hint" => question["answer_hint"]
      )
    end
  end

  # Wall-clock duration in seconds (locked tie-break, shared with QuizAttempt).
  def duration_seconds
    QuizScoring.duration_seconds(started_at, completed_at)
  end

  private

  def play_question_limit_ms(question)
    seconds = question["time_limit_seconds"] ||
              question["effective_limit_seconds"] ||
              QuizScoring::DEFAULT_LIMIT_SECONDS
    seconds.to_i * 1000
  end
end

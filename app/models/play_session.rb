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

  def process_answer!(selected_ids)
    question = current_question
    selected = Array(selected_ids).map(&:to_i).reject(&:zero?)
    correct = Array(question["correct_answer"])

    is_correct = selected.sort == correct.sort
    points = is_correct ? calculate_points : 0
    new_streak = is_correct ? streak + 1 : 0

    # Add response
    self.responses << {
      "question_index" => current_index,
      "selected" => selected,
      "correct_answer" => correct,
      "is_correct" => is_correct,
      "points" => points
    }

    # Update game state
    self.total_score += points
    self.streak = new_streak
    self.current_index += 1

    # Mark complete if finished
    self.completed_at = Time.current if game_complete?

    save!
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

  private

  def calculate_points
    base_points = 1000
    streak_bonus = [ streak * 100, 300 ].min
    base_points + streak_bonus
  end
end

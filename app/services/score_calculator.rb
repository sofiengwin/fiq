# frozen_string_literal: true

# Play scoring entry point for the saved-quiz path (QuizAttempt/Response).
# Delegates to QuizScoring, the single locked formula shared with PlaySession.
# Play never reads quiz.scoring_mode (the column + validations stay for
# non-play code only).
# Q12: the scorer reads only answer_options (+ is_correct), points and time
# limits. Phase-2 shells (question_type/payload, text_answer/payload) and the
# quiz creation record are never consulted here.
class ScoreCalculator
  Result = Struct.new(:raw_score, :time_bonus, :base_score, :streak_bonus,
                      :final_score, :new_streak, :correct?, keyword_init: true)

  def initialize(question:, selected_answer_ids:, time_taken_ms:, current_streak:)
    @question = question
    @selected_answer_ids = Array(selected_answer_ids).map(&:to_i)
    @time_taken_ms = time_taken_ms.to_i
    @current_streak = current_streak.to_i
  end

  def calculate
    scored = QuizScoring.score(
      correct_ids: @question.correct_answer_ids,
      selected_ids: @selected_answer_ids,
      base_points: @question.points || QuizScoring::DEFAULT_BASE_POINTS,
      time_taken_ms: @time_taken_ms,
      effective_limit_ms: effective_limit_ms,
      streak: @current_streak
    )

    Result.new(
      raw_score: scored.correct? ? 1.0 : 0.0,
      time_bonus: scored.time_bonus,
      base_score: scored.time_points,
      streak_bonus: scored.streak_bonus,
      final_score: scored.points,
      new_streak: scored.new_streak,
      correct?: scored.correct?
    )
  end

  private

  def effective_limit_ms
    limit = @question.respond_to?(:effective_time_limit) ? @question.effective_time_limit : nil
    (limit || QuizScoring::DEFAULT_LIMIT_SECONDS).to_i * 1000
  end
end

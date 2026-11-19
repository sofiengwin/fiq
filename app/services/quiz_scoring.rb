# frozen_string_literal: true

# Single locked play-scoring formula (Q2), shared by every play path:
# ScoreCalculator/QuizAttempt (saved quizzes) and PlaySession (/play).
#
# Rules (locked by doc/quiz.md):
# - correct = selected_ids.sort == correct_ids.sort (an empty selection is
#   always wrong, even if a question somehow has no correct options).
# - points = 0 when wrong or timed out; otherwise
#   time_points + streak_bonus, where
#     time_points  = (base_points * time_bonus).round
#     streak_bonus = [incoming streak, 3].min * 100  (max +300)
# - new_streak = correct ? streak + 1 : 0
#
# Speed curve (locked): ratio = clamp(time_taken_ms / effective_limit_ms, 0, 1);
# time_bonus = 1.0 - 0.5 * ratio.
# An instant answer earns the full base; an answer at the limit earns half.
# The curve is linear and strictly decreasing, so for the same question a
# faster correct answer always earns strictly more time_points (integer
# rounding can collapse sub-point gaps to a tie but, being monotonic, can
# never reverse the order).
#
# Tie-break "faster" (locked, reused wherever attempts are ranked, e.g.
# Q10 invited-play comparison and Q11 leaderboard): wall-clock duration
# completed_at - started_at, in seconds. Never a sum of time_taken_ms.
#
# Play never reads quizzes.scoring_mode. The column and its validations stay
# for non-play code only.
#
# Q12: scoring inputs are correct_ids (from answer_options.is_correct),
# base_points, time_taken_ms and streak only. Phase-2 shells
# (question_type/payload, text_answer/payload) and the quiz creation record
# are never read here.
module QuizScoring
  DEFAULT_BASE_POINTS = 1000
  DEFAULT_LIMIT_SECONDS = 20
  DEFAULT_LIMIT_MS = DEFAULT_LIMIT_SECONDS * 1000
  STREAK_STEP = 100
  STREAK_CAP = 3

  Result = Struct.new(:correct, :time_bonus, :time_points, :streak_bonus,
                      :points, :new_streak, keyword_init: true) do
    def correct?
      correct
    end
  end

  def self.score(correct_ids:, selected_ids:, base_points: DEFAULT_BASE_POINTS,
                 time_taken_ms: 0, effective_limit_ms: DEFAULT_LIMIT_MS, streak: 0)
    correct_list = Array(correct_ids).map(&:to_i).sort
    picked = Array(selected_ids).map(&:to_i).sort
    correct = picked.present? && picked == correct_list

    bonus = time_bonus(time_taken_ms, effective_limit_ms)
    time_points = correct ? ((base_points || DEFAULT_BASE_POINTS).to_i * bonus).round : 0
    streak_bonus = correct ? [ streak.to_i, STREAK_CAP ].min * STREAK_STEP : 0

    Result.new(
      correct: correct,
      time_bonus: bonus,
      time_points: time_points,
      streak_bonus: streak_bonus,
      points: time_points + streak_bonus,
      new_streak: correct ? streak.to_i + 1 : 0
    )
  end

  # Timeout scores zero through the same scorer: empty selection + full time.
  def self.timeout(correct_ids:, base_points: DEFAULT_BASE_POINTS,
                   effective_limit_ms: DEFAULT_LIMIT_MS, streak: 0)
    score(
      correct_ids: correct_ids,
      selected_ids: [],
      base_points: base_points,
      time_taken_ms: effective_limit_ms,
      effective_limit_ms: effective_limit_ms,
      streak: streak
    )
  end

  def self.time_bonus(time_taken_ms, effective_limit_ms)
    limit_ms = effective_limit_ms.to_i
    ratio = limit_ms > 0 ? time_taken_ms.to_f / limit_ms : 1.0
    ratio = [ [ ratio, 0.0 ].max, 1.0 ].min
    1.0 - 0.5 * ratio
  end

  # Locked tie-break input: wall-clock seconds from start to finish.
  def self.duration_seconds(started_at, completed_at)
    return nil if started_at.nil? || completed_at.nil?

    completed_at - started_at
  end

  def self.faster?(a_started_at, a_completed_at, b_started_at, b_completed_at)
    a = duration_seconds(a_started_at, a_completed_at)
    b = duration_seconds(b_started_at, b_completed_at)
    return false if a.nil?
    return true if b.nil?

    a < b
  end
end

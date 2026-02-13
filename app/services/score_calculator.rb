# frozen_string_literal: true

class ScoreCalculator
  STREAK_MULTIPLIERS = { 1 => 1.0, 2 => 1.1, 3 => 1.2 }.freeze
  MAX_STREAK_MULTIPLIER = 1.3

  Result = Struct.new(:raw_score, :time_bonus, :base_score, :streak_multiplier,
                      :final_score, :new_streak, :correct?, keyword_init: true)

  def initialize(question:, selected_answer_ids:, time_taken_ms:, current_streak:)
    @question = question
    @selected_answer_ids = Array(selected_answer_ids).map(&:to_i)
    @time_taken_ms = time_taken_ms.to_i
    @current_streak = current_streak.to_i
  end

  def calculate
    @correct_ids = @question.answer_options.where(is_correct: true).pluck(:id)
    @raw_score = calculate_raw_score
    @time_bonus = calculate_time_bonus
    @base_score = (@question.points * @raw_score * (0.5 + @time_bonus)).round
    @new_streak = @raw_score > 0 ? @current_streak + 1 : 0
    @streak_multiplier = calculate_streak_multiplier
    @final_score = (@base_score * @streak_multiplier).round

    Result.new(
      raw_score: @raw_score,
      time_bonus: @time_bonus,
      base_score: @base_score,
      streak_multiplier: @streak_multiplier,
      final_score: @final_score,
      new_streak: @new_streak,
      correct?: @raw_score > 0
    )
  end

  private

  def calculate_raw_score
    return 0.0 if @selected_answer_ids.empty?

    case @question.quiz.scoring_mode
    when "partial_credit"
      calculate_partial_credit
    when "all_or_nothing"
      @selected_answer_ids.sort == @correct_ids.sort ? 1.0 : 0.0
    else
      calculate_partial_credit # Default to partial credit
    end
  end

  def calculate_partial_credit
    return 0.0 if @correct_ids.empty?

    correct_selections = (@selected_answer_ids & @correct_ids).size
    incorrect_selections = (@selected_answer_ids - @correct_ids).size

    if incorrect_selections > 0
      [ (correct_selections - incorrect_selections).to_f / @correct_ids.size, 0 ].max
    else
      correct_selections.to_f / @correct_ids.size
    end
  end

  def calculate_time_bonus
    time_limit_ms = @question.effective_time_limit * 1000
    return 0.5 if time_limit_ms <= 0

    bonus = 1.0 - (@time_taken_ms.to_f / time_limit_ms) * 0.5
    [ [ bonus, 0.5 ].max, 1.0 ].min # Clamp between 0.5 and 1.0
  end

  def calculate_streak_multiplier
    STREAK_MULTIPLIERS[@new_streak] || MAX_STREAK_MULTIPLIER
  end
end

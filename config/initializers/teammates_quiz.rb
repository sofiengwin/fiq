# frozen_string_literal: true

module TeammatesQuiz
  CONFIG = {
    group_size: {
      min: 4,
      max: 6,
      default: 5
    },
    overlap_years: {
      min: 1,
      max: 4,
      default: 1
    }
  }.freeze

  DIFFICULTY_PRESETS = {
    easy:   { group_size: 4, min_overlap_years: 1 },
    medium: { group_size: 5, min_overlap_years: 2 },
    hard:   { group_size: 6, min_overlap_years: 3 },
    expert: { group_size: 6, min_overlap_years: 4 }
  }.freeze

  def self.days_for_years(years)
    years.clamp(CONFIG[:overlap_years][:min], CONFIG[:overlap_years][:max]) * 365
  end

  def self.preset_for(difficulty)
    DIFFICULTY_PRESETS.fetch(difficulty.to_sym, DIFFICULTY_PRESETS[:medium])
  end

  def self.validate_group_size(size)
    size.to_i.clamp(CONFIG[:group_size][:min], CONFIG[:group_size][:max])
  end

  def self.validate_overlap_years(years)
    years.to_i.clamp(CONFIG[:overlap_years][:min], CONFIG[:overlap_years][:max])
  end
end

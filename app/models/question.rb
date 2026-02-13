class Question < ApplicationRecord
  # Associations
  belongs_to :quiz
  has_many :answer_options, -> { order(:order_index) }, dependent: :destroy
  has_many :responses, dependent: :destroy

  # Nested attributes
  accepts_nested_attributes_for :answer_options, allow_destroy: true, reject_if: :all_blank

  # Validations
  validates :text, presence: true
  validates :points, numericality: { greater_than: 0 }
  validates :time_limit_seconds, numericality: { greater_than: 0, allow_nil: true }
  validate :at_least_one_correct_answer

  # Defaults
  attribute :points, :integer, default: 1000
  attribute :order_index, :integer, default: 0

  # Constants for Kahoot-style colors
  COLORS = %w[red blue green yellow orange purple].freeze

  def effective_time_limit
    time_limit_seconds || quiz.time_limit_seconds || 20
  end

  def correct_answer_ids
    answer_options.where(is_correct: true).pluck(:id)
  end

  private

  def at_least_one_correct_answer
    return if answer_options.empty? # Allow during creation before answers are added
    return if answer_options.any?(&:is_correct)

    errors.add(:base, "must have at least one correct answer")
  end
end

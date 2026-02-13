class AnswerOption < ApplicationRecord
  # Associations
  belongs_to :question
  has_many :response_answers, dependent: :destroy
  has_many :responses, through: :response_answers

  # Validations
  validates :text, presence: true
  validates :color, inclusion: { in: Question::COLORS }, allow_nil: true

  # Defaults
  attribute :is_correct, :boolean, default: false
  attribute :order_index, :integer, default: 0

  # Scopes
  scope :correct, -> { where(is_correct: true) }
end

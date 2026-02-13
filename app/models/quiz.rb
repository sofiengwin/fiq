class Quiz < ApplicationRecord
  # Associations
  has_many :questions, -> { order(:order_index) }, dependent: :destroy
  has_many :quiz_attempts, dependent: :destroy

  # Nested attributes
  accepts_nested_attributes_for :questions, allow_destroy: true, reject_if: :all_blank

  # Validations
  validates :title, presence: true
  validates :scoring_mode, inclusion: { in: %w[partial_credit all_or_nothing] }
  validates :time_limit_seconds, numericality: { greater_than: 0, allow_nil: true }

  # Scopes
  scope :search, ->(query) { where("title ILIKE ?", "%#{query}%") if query.present? }

  # Defaults
  attribute :scoring_mode, :string, default: "partial_credit"
  attribute :time_limit_seconds, :integer, default: 20

  def duplicate
    new_quiz = dup
    new_quiz.title = "#{title} (Copy)"
    new_quiz.save!

    questions.each do |question|
      new_question = question.dup
      new_question.quiz = new_quiz
      new_question.save!

      question.answer_options.each do |answer|
        new_answer = answer.dup
        new_answer.question = new_question
        new_answer.save!
      end
    end

    new_quiz
  end

  def question_count
    questions.size
  end
end

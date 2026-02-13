class Response < ApplicationRecord
  # Associations
  belongs_to :quiz_attempt
  belongs_to :question
  has_many :response_answers, dependent: :destroy
  has_many :selected_answers, through: :response_answers, source: :answer_option

  # Callbacks
  before_create :set_submitted_at

  def correct?
    score_awarded.present? && score_awarded > 0
  end

  def selected_answer_ids
    selected_answers.pluck(:id)
  end

  private

  def set_submitted_at
    self.submitted_at ||= Time.current
  end
end

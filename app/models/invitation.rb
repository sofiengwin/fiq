# frozen_string_literal: true

# Q9 — Stable invitation link: one row per (quiz, inviter). The token is
# generated once (SecureRandom.urlsafe_base64) and never changes, so the
# same player minting twice gets the same URL.
class Invitation < ApplicationRecord
  belongs_to :quiz
  belongs_to :inviter, class_name: "User", foreign_key: "inviter_user_id"
  has_many :quiz_attempts, dependent: :nullify

  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  # Find-or-create the single stable invitation for this (quiz, inviter)
  # pair. Retries once on a token/row race (unique index guards both).
  def self.stable_for(quiz, user)
    find_or_create_by!(quiz: quiz, inviter: user)
  rescue ActiveRecord::RecordNotUnique
    find_by!(quiz: quiz, inviter: user)
  end

  private

  def generate_token
    self.token ||= loop do
      candidate = SecureRandom.urlsafe_base64(12)
      break candidate unless self.class.exists?(token: candidate)
    end
  end
end

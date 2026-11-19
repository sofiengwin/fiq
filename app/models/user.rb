class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :sent_invitations, class_name: "Invitation",
                              foreign_key: "inviter_user_id",
                              dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def admin?
    admin_since.present?
  end

  # Q11 leaderboard display name. Users have no name column, so the board
  # shows the email handle (part before @).
  def display_name
    email_address.to_s.split("@").first.to_s
  end
end

# frozen_string_literal: true

class AdminAuthorizationAdapter < ActiveAdmin::AuthorizationAdapter
  def authorized?(action, subject = nil)
    return false unless user&.admin?

    true
  end
end

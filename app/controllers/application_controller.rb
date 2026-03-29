class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # ActiveAdmin authentication
  def authenticate_admin!
    pp "Authenticating admin user..."
    pp current_admin_user
    pp Current.user
    unless current_admin_user&.admin?
      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end

  def current_admin_user
    if authenticated? && Current.user&.admin?
      Current.user
    end
  end
end

class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # ActiveAdmin authentication
  def authenticate_admin!
    # Ensure session is set for ActiveAdmin controllers
    Current.session ||= Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]

    unless Current.user&.admin?
      redirect_to root_path, alert: "You are not authorized to access this page."
    end
  end

  def current_admin_user
    Current.session ||= Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    Current.user if Current.user&.admin?
  end
end

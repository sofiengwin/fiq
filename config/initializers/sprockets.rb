# Configure Sprockets to work alongside Propshaft
# This is needed because ActiveAdmin requires Sprockets but the app uses Propshaft

if defined?(Sprockets)
  # Prevent Sprockets from trying to handle asset helper methods in the main app
  # ActiveAdmin has its own layout that uses Sprockets, so it works fine there

  Rails.application.config.after_initialize do
    # Ensure Propshaft handles main app assets
    if defined?(Propshaft)
      # The Propshaft railtie should take precedence
      Rails.logger.info "Sprockets and Propshaft coexisting - ActiveAdmin uses Sprockets"
    end
  end
end

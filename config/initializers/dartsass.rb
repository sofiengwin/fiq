# Configure dartsass-rails to compile multiple files including ActiveAdmin
Rails.application.configure do
  # Add active_admin.scss to the list of files to compile
  config.dartsass.builds = {
    "application.scss" => "application.css",
    "active_admin.scss" => "active_admin.css"
  }

  # Add the ActiveAdmin gem's stylesheets directory to asset paths
  # dartsass-rails uses config.assets.paths for --load-path arguments
  activeadmin_gem = Gem.loaded_specs["activeadmin"]
  if activeadmin_gem
    activeadmin_stylesheets = File.join(activeadmin_gem.gem_dir, "app", "assets", "stylesheets")
    config.assets.paths << activeadmin_stylesheets
  end
end

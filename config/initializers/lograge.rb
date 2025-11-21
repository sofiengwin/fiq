Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.base_controller_class = "ActionController::API"

  config.lograge.custom_options = lambda do |event|
    { name: "lograge", host: "fiq_host", environment: Rails.env }
  end
end

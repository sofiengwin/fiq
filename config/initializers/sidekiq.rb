SIDEKIQ_REDIS_URL = ENV["REDIS_URL_SIDEKIQ"]
puts SIDEKIQ_REDIS_URL
puts SIDEKIQ_REDIS_URL
puts SIDEKIQ_REDIS_URL
puts SIDEKIQ_REDIS_URL
puts SIDEKIQ_REDIS_URL
puts SIDEKIQ_REDIS_URL
pp ActiveRecord::Base.connection_db_config.configuration_hash
pp Rails.env

sidekiq_redis = { url: SIDEKIQ_REDIS_URL }

Sidekiq.configure_server do |config|
  config.redis = sidekiq_redis
end

Sidekiq.configure_client do |config|
  config.redis = sidekiq_redis
end

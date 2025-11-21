class LoggerWorker
  include Sidekiq::Worker

  def perform
    Rails.logger.info("LoggerWorker is running")
  end
end

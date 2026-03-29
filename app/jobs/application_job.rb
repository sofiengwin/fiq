class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encounter a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on API failures with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # Log job execution
  around_perform do |job, block|
    Rails.logger.info "[#{job.class.name}] Starting with args: #{job.arguments.inspect}"
    block.call
    Rails.logger.info "[#{job.class.name}] Completed successfully"
  rescue => e
    Rails.logger.error "[#{job.class.name}] Failed: #{e.message}"
    raise
  end

  def wait_time
    last_execution = SolidQueue::ScheduledExecution.last
    return Time.current if last_execution.nil?

    last_execution.scheduled_at + 30.seconds
  end
end

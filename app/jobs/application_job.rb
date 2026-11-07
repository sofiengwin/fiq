class ApplicationJob < ActiveJob::Base
  # L8 priority: batch runs synchronously (operator rake, never queued) so it
  # never waits; queued work claims lower numbers first (Solid Queue):
  # nightly (10) before auto fan-out (50, this default).
  queue_with_priority AutoDiscovery::AUTO_PRIORITY

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

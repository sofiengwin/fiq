require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
  extend Limiter::Mixin

  class FootballClientRateLimitExceeded < StandardError; end

  # Rate limit: 300 requests per minute (skip in test environment)
  unless Rails.env.test?
    limit_method(:call, rate: 450, interval: 60, balanced: true) do
      Rails.logger.info("FootballClient rate limit exceeded")
      raise FootballClientRateLimitExceeded, "Rate limit exceeded"
    end
  end

  BASE_URL = "https://v3.football.api-sports.io/"

  # L1 live-only: minimum spacing between live API calls in the same process
  # (seconds). Applies in addition to the Limiter above. Overridable via env
  # (tests).
  THROTTLE_SECONDS = 0.6
  THROTTLE_ENV_VAR = "FOOTBALL_CLIENT_THROTTLE_SECONDS"

  class << self
    def throttle_mutex
      @throttle_mutex ||= Mutex.new
    end

    def last_request_at
      @last_request_at
    end

    def last_request_at=(value)
      @last_request_at = value
    end

    # Test hook: forget the last live-request timestamp.
    def reset_throttle!
      self.last_request_at = nil
    end

    def throttle_interval
      ENV.fetch(THROTTLE_ENV_VAR, THROTTLE_SECONDS.to_s).to_f
    end
  end

  def initialize(end_point:)
    @end_point = end_point
    @url = URI("#{BASE_URL}#{@end_point}")
  end

  # L1 live-only: throttle → live request → handle_response, zero file I/O.
  def call
    body = fetch_live
    handle_response(body)
  rescue StandardError => e
    Rails.logger.error("FootballClient Error: #{e.message}")
    raise e
  end

  private

  # Minimum spacing between live calls in this process (throttle).
  def throttle!
    interval = self.class.throttle_interval
    return if interval <= 0

    self.class.throttle_mutex.synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      last = self.class.last_request_at
      if last
        wait = interval - (now - last)
        if wait.positive?
          Rails.logger.info("FootballClient throttle: waiting #{format("%.3f", wait)}s before live request")
          sleep(wait)
        end
      end
      self.class.last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def fetch_live
    throttle!
    Rails.logger.info("FootballClient live request: #{@end_point}")
    make_request.body
  end

  # Credential headers and errors.rateLimit handling.
  def handle_response(body)
    response = JSON.parse(body, symbolize_names: true)
    if response[:errors].present?
      if response[:errors][:rateLimit].present?
        raise FootballClientRateLimitExceeded, "API rate limit exceeded: #{response[:errors][:rateLimit]}"
      else
        raise StandardError, "API error: #{response[:errors]}"
      end
    end

    response[:response]
  end

  def make_request
    request = Net::HTTP::Get.new(@url)
    request["x-rapidapi-host"] = Rails.application.credentials.dig(:football_api, :host)
    request["x-rapidapi-key"] = Rails.application.credentials.dig(:football_api, :api_key)

    Net::HTTP.start(@url.hostname, @url.port, use_ssl: true) do |http|
      http.request(request)
    end
  end
end

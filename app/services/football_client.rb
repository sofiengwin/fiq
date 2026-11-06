require "uri"
require "net/http"
require "openssl"
require "digest"
require "fileutils"

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

  # T2: minimum spacing between live API calls in the same process (seconds).
  # Applies in addition to the Limiter above. Overridable via env (tests).
  THROTTLE_SECONDS = 0.6
  THROTTLE_ENV_VAR = "FOOTBALL_CLIENT_THROTTLE_SECONDS"

  # T2: read-through cache flag. Default is cache-on in every env; tests opt
  # out via this env flag or the explicit `cache:` param. An explicit param
  # always wins over the env flag.
  CACHE_ENV_VAR = "FOOTBALL_CLIENT_CACHE"
  CACHE_DISABLED_VALUES = %w[0 false no off].freeze

  class << self
    # Base directory for cache files. data/raw/ outside test so cached
    # payloads are visible to the probe (T3) and backfill (T5); tmp/ in test
    # so stubbed responses never pollute data/raw/.
    def cache_dir
      @cache_dir ||= default_cache_dir
    end

    attr_writer :cache_dir

    def default_cache_dir
      if Rails.env.test?
        Rails.root.join("tmp/cache/football_client")
      else
        Rails.root.join("data/raw")
      end
    end

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

  def initialize(end_point:, cache: nil)
    @end_point = end_point
    @cache_override = cache
    @url = URI("#{BASE_URL}#{@end_point}")
  end

  def call
    if cache_enabled? && (cached_body = read_cache)
      Rails.logger.info("FootballClient cache hit: #{@end_point}")
      return handle_response(cached_body)
    end

    body = fetch_live
    response = handle_response(body)
    write_cache(body) if cache_enabled?
    response
  rescue StandardError => e
    Rails.logger.error("FootballClient Error: #{e.message}")
    raise e
  end

  private

  def cache_enabled?
    return @cache_override unless @cache_override.nil?

    !CACHE_DISABLED_VALUES.include?(ENV.fetch(CACHE_ENV_VAR, "true").to_s.strip.downcase)
  end

  # Deterministic file for this endpoint+params: endpoint slug + sorted-query hash.
  def cache_path
    path, query = @end_point.split("?", 2)
    slug = path.to_s.tr("/", "_").gsub(/[^A-Za-z0-9_.\-]/, "_")
    slug = "root" if slug.empty?
    digest =
      if query.nil? || query.empty?
        "noquery"
      else
        canonical = URI.decode_www_form(query).sort.map { |k, v| "#{k}=#{v}" }.join("&")
        Digest::SHA256.hexdigest(canonical)
      end
    self.class.cache_dir.join("#{slug}__#{digest}.json")
  end

  def read_cache
    path = cache_path
    return unless File.exist?(path)

    File.read(path)
  end

  # Only successful payloads reach the write: handle_response raises on API
  # errors before we get here, so error bodies never poison the cache.
  def write_cache(body)
    path = cache_path
    FileUtils.mkdir_p(path.dirname)
    tmp_path = "#{path}.#{Process.pid}.tmp"
    File.write(tmp_path, body)
    File.rename(tmp_path, path)
    Rails.logger.info("FootballClient cache write: #{path}")
  rescue StandardError => e
    Rails.logger.warn("FootballClient cache write failed (#{path}): #{e.message}")
  end

  # Minimum spacing between live calls in this process (T2 throttle).
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

  # Shared by live and cached bodies so replayed payloads behave identically
  # (credential headers and errors.rateLimit handling unchanged).
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

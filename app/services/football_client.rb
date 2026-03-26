require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
  extend Limiter::Mixin

  # Rate limit: 300 requests per minute (skip in test environment)
  unless Rails.env.test?
    limit_method(:call, rate: 300, interval: 60, balanced: true) do
      Rails.logger.info("FootballClient rate limit exceeded")
      raise StandardError, "Rate limit exceeded"
    end
  end

  BASE_URL = "https://v3.football.api-sports.io/"

  def initialize(end_point:)
    @end_point = end_point
    @url = URI("#{BASE_URL}#{@end_point}")
  end

  def call
    response = JSON.parse(make_request.body, symbolize_names: true)
    raise StandardError, response[:errors] if response[:errors].present?
    response[:response]
  rescue StandardError => e
    Rails.logger.error("FootballClient Error: #{e.message}")
    raise e
  end

  private

  def make_request
    request = Net::HTTP::Get.new(@url)
    request["x-rapidapi-host"] = Rails.application.credentials.dig(:football_api, :host)
    request["x-rapidapi-key"] = Rails.application.credentials.dig(:football_api, :api_key)

    Net::HTTP.start(@url.hostname, @url.port, use_ssl: true) do |http|
      http.request(request)
    end
  end
end

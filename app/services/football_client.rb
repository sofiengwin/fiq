require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
  extend Limiter::Mixin

  limit_method(:call, rate: 10, interval: 60, balanced: true) do
    Rails.logger.info("FootballClient rate limit exceeded")
    raise StandardError, "Rate limit exceeded"
  end

  BASE_URL = "https://v3.football.api-sports.io/"
  def initialize(end_point:)
    @end_point = end_point
    @url = URI("https://v3.football.api-sports.io/#{@end_point}")
  end

  def call
    response = JSON.parse(make_request.body, symbolize_names: true)
    if response[:error]
      raise StandardError, response[:error]
    end
    response[:response]
  rescue StandardError => e
    Rails.logger.error("FootballClient Error: #{e.message}")
    raise e
  end

  private

  def make_request
    request = Net::HTTP::Get.new(@url)
    request["x-rapidapi-host"] = Rails.application.credentials.development[:football_api][:host]
    request["x-rapidapi-key"] = Rails.application.credentials.development[:football_api][:api_key]

    Net::HTTP.start(@url.hostname, @url.port, use_ssl: @url.scheme == "https") do |http|
      http.request(request)
    end
  end

  def url
    BASE_URL + @end_point
  end
end

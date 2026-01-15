require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
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
    request["x-rapidapi-host"] = "v3.football.api-sports.io"
    request["x-rapidapi-key"] = "fcc0de36de0119b7886c6b8742ee0317"

    Net::HTTP.start(@url.hostname, @url.port, use_ssl: @url.scheme == "https") do |http|
      http.request(request)
    end
  end

  def url
    BASE_URL + @end_point
  end
end

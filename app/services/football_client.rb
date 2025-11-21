require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
  BASE_URL = "https://v3.football.api-sports.io/"
  def initialize(end_point:)
    @end_point = end_point

    @url = URI("https://v3.football.api-sports.io/#{@end_point}")

    @http = Net::HTTP.new(url.host)
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end

  def call
    JSON.parse(make_request.body, symbolize_keys: true)
  end

  private

  def make_request
    request = Net::HTTP::Get.new(@url)
    request["x-rapidapi-host"] = "v3.football.api-sports.io"
    request["x-rapidapi-key"] = "XxXxXxXxXxXxXxXxXxXxXxXx"

    http.request(request)
  end

  def url
    BASE_URL + @end_point
  end
end

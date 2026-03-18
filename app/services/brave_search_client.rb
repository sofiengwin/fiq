# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class BraveSearchClient < ApplicationService
  BASE_URL = "https://api.search.brave.com/res/v1/chat/completions"

  def initialize(query:, options: {})
    @query = query
    @options = options
  end

  def call
    uri = URI(BASE_URL)
    request = build_request(uri)

    response = execute_request(uri, request)
    parse_response(response)
  end

  private

  def api_key
    Rails.application.credentials.dig(:brave, :api_key) ||
      ENV.fetch("BRAVE_API_KEY", nil)
  end

  def build_request(uri)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-subscription-token"] = api_key

    body = {
      stream: false,
      model: "brave",
      messages: [
        { role: "user", content: @query }
      ]
    }.merge(@options)

    request.body = JSON.generate(body)
    request
  end

  def execute_request(uri, request)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = 30
      http.open_timeout = 10
      http.request(request)
    end
  end

  def parse_response(response)
    case response
    when Net::HTTPSuccess
      result = JSON.parse(response.body)
      extract_content(result)
    else
      Rails.logger.error("BraveSearchClient error: #{response.code} - #{response.message}")
      { error: response.code, message: response.message, body: response.body }
    end
  end

  def extract_content(result)
    return result unless result["choices"]&.first&.dig("message", "content")

    content = result["choices"].first["message"]["content"]
    # Remove markdown code blocks if present
    content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      JSON.parse(content, symbolize_names: true)
    rescue JSON::ParserError => e
      Rails.logger.warn("BraveSearchClient: Failed to parse JSON response - #{e.message}")
      { raw_content: content }
    end
  end
end

require "test_helper"

class FootballClientTest < ActiveSupport::TestCase
  include WebMock::API

  ENDPOINT = "teams?league=39&season=2023".freeze
  URL = "https://v3.football.api-sports.io/#{ENDPOINT}".freeze
  PAYLOAD = { response: [ { team: { id: 33, name: "Manchester United" } } ], errors: {} }.to_json.freeze

  setup do
    WebMock.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
  end

  test "every identical call costs a live HTTP request" do
    stub = stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)

    first = FootballClient.call(end_point: ENDPOINT)
    second = FootballClient.call(end_point: ENDPOINT)

    assert_requested(stub, times: 2)
    assert_equal first, second
  end

  test "back-to-back live calls are spaced at least 0.6s apart" do
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0.6"
    FootballClient.reset_throttle!
    stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)
    other = "teams?league=39&season=2022"
    stub_request(:get, "https://v3.football.api-sports.io/#{other}").to_return(status: 200, body: PAYLOAD)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    FootballClient.call(end_point: ENDPOINT)
    FootballClient.call(end_point: other)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :>=, 0.55
  end

  test "rate-limit payload raises and retries cost live HTTP" do
    error_body = { response: [], errors: { rateLimit: "Too many requests" } }.to_json
    stub = stub_request(:get, URL).to_return(status: 200, body: error_body)

    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      FootballClient.call(end_point: ENDPOINT)
    end
    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      FootballClient.call(end_point: ENDPOINT)
    end

    assert_requested(stub, times: 2)
  end

  test "non-rate-limit API errors raise StandardError" do
    error_body = { response: [], errors: { requests: "Invalid parameters" } }.to_json
    stub = stub_request(:get, URL).to_return(status: 200, body: error_body)

    assert_raises(StandardError) do
      FootballClient.call(end_point: ENDPOINT)
    end

    assert_requested(stub, times: 1)
  end
end

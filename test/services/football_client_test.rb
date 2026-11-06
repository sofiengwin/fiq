require "test_helper"
require "tmpdir"

class FootballClientTest < ActiveSupport::TestCase
  include WebMock::API

  ENDPOINT = "teams?league=39&season=2023".freeze
  URL = "https://v3.football.api-sports.io/#{ENDPOINT}".freeze
  PAYLOAD = { response: [ { team: { id: 33, name: "Manchester United" } } ], errors: {} }.to_json.freeze

  setup do
    WebMock.reset!
    @tmpdir = Dir.mktmpdir
    @original_cache_dir = FootballClient.cache_dir
    FootballClient.cache_dir = Pathname.new(@tmpdir)
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(
      FootballClient::CACHE_ENV_VAR,
      FootballClient::THROTTLE_ENV_VAR
    )
    ENV[FootballClient::CACHE_ENV_VAR] = "true"
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.cache_dir = @original_cache_dir
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::CACHE_ENV_VAR)
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@tmpdir)
  end

  test "first call hits network once and writes cache file, second identical call makes zero HTTP" do
    stub = stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)

    first = FootballClient.call(end_point: ENDPOINT)
    second = FootballClient.call(end_point: ENDPOINT)

    assert_requested(stub, times: 1)
    assert_equal first, second
    assert_equal 1, Dir.children(@tmpdir).count { |f| f.end_with?(".json") }
  end

  test "cache key is deterministic regardless of param order" do
    stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)
    reordered = "teams?season=2023&league=39"
    stub_request(:get, "https://v3.football.api-sports.io/#{reordered}").to_return(status: 200, body: PAYLOAD)

    FootballClient.call(end_point: ENDPOINT)
    FootballClient.call(end_point: reordered)

    assert_equal 1, Dir.children(@tmpdir).count { |f| f.end_with?(".json") }
  end

  test "back-to-back live calls are spaced at least 0.6s apart" do
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0.6"
    FootballClient.reset_throttle!
    stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)
    other = "teams?league=39&season=2022"
    stub_request(:get, "https://v3.football.api-sports.io/#{other}").to_return(status: 200, body: PAYLOAD)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    FootballClient.call(end_point: ENDPOINT, cache: false)
    FootballClient.call(end_point: other, cache: false)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :>=, 0.55
  end

  test "cache opt-out via explicit param makes a live call every time and writes nothing" do
    stub = stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)

    FootballClient.call(end_point: ENDPOINT, cache: false)
    FootballClient.call(end_point: ENDPOINT, cache: false)

    assert_requested(stub, times: 2)
    assert_empty Dir.children(@tmpdir)
  end

  test "cache opt-out via env flag makes a live call every time" do
    ENV[FootballClient::CACHE_ENV_VAR] = "false"
    stub = stub_request(:get, URL).to_return(status: 200, body: PAYLOAD)

    FootballClient.call(end_point: ENDPOINT)
    FootballClient.call(end_point: ENDPOINT)

    assert_requested(stub, times: 2)
    assert_empty Dir.children(@tmpdir)
  end

  test "API error payloads are never cached" do
    error_body = { response: [], errors: { rateLimit: "Too many requests" } }.to_json
    stub = stub_request(:get, URL).to_return(status: 200, body: error_body)

    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      FootballClient.call(end_point: ENDPOINT)
    end
    assert_raises(FootballClient::FootballClientRateLimitExceeded) do
      FootballClient.call(end_point: ENDPOINT)
    end

    assert_requested(stub, times: 2)
    assert_empty Dir.children(@tmpdir)
  end
end

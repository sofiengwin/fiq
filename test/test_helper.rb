ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "vcr"
require "sidekiq/testing"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock

  # Filter out sensitive data
  config.filter_sensitive_data("<FOOTBALL_API_KEY>") do
    Rails.application.credentials.development[:football_api][:api_key]
  end

  config.filter_sensitive_data("<FOOTBALL_API_HOST>") do
    Rails.application.credentials.development[:football_api][:host]
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "vcr"

# Configure VCR for API testing
VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock

  # Filter sensitive data
  config.filter_sensitive_data("<FOOTBALL_API_KEY>") do
    Rails.application.credentials.dig(:football_api, :api_key)
  end

  config.filter_sensitive_data("<FOOTBALL_API_HOST>") do
    Rails.application.credentials.dig(:football_api, :host)
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include ActiveJob test helpers
    include ActiveJob::TestHelper

    # Add more helper methods to be used by all tests here...
  end
end

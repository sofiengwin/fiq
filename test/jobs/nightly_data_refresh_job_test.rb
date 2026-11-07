# frozen_string_literal: true

require "test_helper"

# L6 — NightlyDataRefreshJob (live-only): thin wrapper pinning the team_sync queue and
# the dry-run passthrough to Pl39NightlyRefresh (behavior covered there).
class NightlyDataRefreshJobTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.reset!
  end

  teardown do
    WebMock.reset!
  end

  test "runs on the team_sync queue" do
    assert_equal "team_sync", NightlyDataRefreshJob.new.queue_name
  end

  test "dry-run delegates without HTTP and reports stale counts" do
    country = Country.find_or_create_by!(name: "T7 Jobland")
    FootballTeam.create!(name: "T7 Job Team", external_id: "781", country: country, last_refreshed_at: nil)
    FootballTeam.create!(name: "T7 Fresh Team", external_id: "782", country: country, last_refreshed_at: Time.current)

    result = NightlyDataRefreshJob.perform_now(dry_run: true)

    assert_equal true, result[:dry_run]
    assert_equal 1, result[:teams]
    assert_equal 1, result[:total]
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
    assert_nil FootballTeam.find_by!(external_id: "781").last_refreshed_at
  end
end

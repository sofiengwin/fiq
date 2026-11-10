require "test_helper"
require "rake"
require "yaml"
require "fugit"

# L6 — data:nightly_refresh rake wrapper, live-only (dry-run default, zero HTTP) plus
# the config/recurring.yml data_refresh entry: daily 02:00 UTC on team_sync.
# Refresh behavior itself is covered in LeagueNightlyRefreshTest; here only
# the rake plumbing and the schedule entry are pinned.
class DataNightlyRefreshRakeTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.reset!
    Rake::Task.define_task(:environment)
    unless Rake::Task.task_defined?("data:nightly_refresh")
      load Rails.root.join("lib/tasks/nightly_refresh.rake")
    end
    @task = Rake::Task["data:nightly_refresh"]
    @task.reenable
  end

  teardown do
    WebMock.reset!
    @task.reenable if @task
  end

  test "default invocation is a dry-run with zero HTTP" do
    country = Country.find_or_create_by!(name: "T7 Rakeland")
    FootballTeam.create!(name: "T7 Rake Team", external_id: "791", country: country, last_refreshed_at: nil)

    out, = capture_io { @task.invoke }

    assert_includes out, "nightly_refresh:"
    assert_includes out, "dry_run=true"
    assert_includes out, "total=1"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
    assert_nil FootballTeam.find_by!(external_id: "791").last_refreshed_at
  end

  test "recurring.yml schedules data_refresh daily at 02:00 UTC on team_sync" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    entry = config.fetch("production").fetch("data_refresh")

    assert_equal "NightlyDataRefreshJob", entry.fetch("class")
    assert_equal "team_sync", entry.fetch("queue")

    schedule = entry.fetch("schedule")
    assert_includes schedule, "2am"
    parsed = Fugit.parse(schedule)
    assert_instance_of Fugit::Cron, parsed
    assert_match(/0 2 \* \* \*/, parsed.original)
  end

  test "recurring data_refresh entry maps to an existing job class" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    class_name = config.fetch("production").fetch("data_refresh").fetch("class")

    assert_equal "team_sync", class_name.constantize.new.queue_name
  end
end

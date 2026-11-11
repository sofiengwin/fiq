require "test_helper"
require "rake"

# data:backfill_league rake wrapper: always enqueues BackfillLeagueJob (never
# runs inline, so enqueue costs zero HTTP). An explicit season enqueues one
# job as-is; omitting season fans out one job per convention-range season
# except fresh-dead memos. Missing league_id exits 1 with nothing enqueued.
# End-to-end backfill behavior is covered in LeagueBackfillTest; delegation
# in BackfillLeagueJobTest.
class DataBackfillLeagueRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebMock::API

  setup do
    WebMock.reset!
    Rake::Task.define_task(:environment)
    unless Rake::Task.task_defined?("data:backfill_league")
      load Rails.root.join("lib/tasks/backfill_league.rake")
    end
    @task = Rake::Task["data:backfill_league"]
    @task.reenable
  end

  teardown do
    WebMock.reset!
    @task.reenable if @task
  end

  test "missing args refuse with exit 1, zero HTTP, and nothing enqueued" do
    out, = capture_io do
      assert_no_enqueued_jobs do
        raised = assert_raises(SystemExit) { @task.invoke }
        assert_equal 1, raised.status
      end
    end

    assert_includes out, "status=refused"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "valid args enqueue the job with args and zero HTTP at enqueue" do
    out, = capture_io do
      assert_enqueued_with(job: BackfillLeagueJob) do
        @task.invoke("39", "2022")
      end
    end

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |entry|
      (entry[:job] || entry["job"]) == BackfillLeagueJob
    end
    assert_equal 1, enqueued.size
    args = enqueued.first[:args] || enqueued.first["args"]
    assert_equal 39, args[0]
    assert_equal 2022, args[1]
    assert_includes args.inspect, "max_requests"

    assert_includes out, "status=enqueued"
    assert_includes out, "BackfillLeagueJob"
    assert_includes out, "job_id="
    assert_includes out, "season=2022"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "no season enqueues all in-range seasons with zero HTTP" do
    expected = (LeagueSeason::FIRST_SEASON..Time.zone.now.year).to_a

    out, = capture_io do
      assert_enqueued_jobs expected.size do
        @task.invoke("39")
      end
    end

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |entry|
      (entry[:job] || entry["job"]) == BackfillLeagueJob
    end
    seasons = enqueued.map { |entry| (entry[:args] || entry["args"])[1] }.sort
    assert_equal expected, seasons

    assert_includes out, "status=enqueued_all"
    assert_includes out, "enqueued=#{expected.size}"
    assert_includes out, "skipped=0"
    assert_includes out, "enqueued_seasons=#{expected.join(",")}"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "no season skips fresh-dead memos with zero HTTP" do
    dead_season = LeagueSeason::FIRST_SEASON
    LeagueSeason.record_contact!(
      league_id: 39, season: dead_season,
      status: LeagueSeason::DEAD, team_count: 0, reason: "empty teams response"
    )
    expected = ((LeagueSeason::FIRST_SEASON..Time.zone.now.year).to_a - [ dead_season ])

    out, = capture_io do
      assert_enqueued_jobs expected.size do
        @task.invoke("39")
      end
    end

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |entry|
      (entry[:job] || entry["job"]) == BackfillLeagueJob
    end
    seasons = enqueued.map { |entry| (entry[:args] || entry["args"])[1] }.sort
    assert_equal expected, seasons
    assert_not_includes seasons, dead_season

    assert_includes out, "status=enqueued_all"
    assert_includes out, "enqueued=#{expected.size}"
    assert_includes out, "skipped=1"
    assert_includes out, "skipped_seasons=#{dead_season}"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end
end

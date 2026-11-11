require "test_helper"
require "rake"

# data:backfill_league rake wrapper: always enqueues BackfillLeagueJob (never
# runs inline, so enqueue costs zero HTTP) and exits 1 with nothing enqueued
# on missing args. End-to-end backfill behavior is covered in
# LeagueBackfillTest; delegation in BackfillLeagueJobTest.
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
end

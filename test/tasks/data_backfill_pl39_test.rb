require "test_helper"
require "rake"

# T5 — data:backfill_pl39 rake wrapper: bounded entry point that refuses
# invalid seasons (exit 1, zero HTTP) and runs the service otherwise.
# End-to-end backfill behavior is covered in LeagueBackfillTest; here only the
# refusal plumbing and exit codes are pinned.
class DataBackfillPl39RakeTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.reset!
    Rake::Task.define_task(:environment)
    unless Rake::Task.task_defined?("data:backfill_pl39")
      load Rails.root.join("lib/tasks/backfill_pl39.rake")
    end
    @task = Rake::Task["data:backfill_pl39"]
    @task.reenable
  end

  teardown do
    WebMock.reset!
    @task.reenable if @task
  end

  test "missing season argument refuses with exit 1 and zero HTTP" do
    out, = capture_io do
      raised = assert_raises(SystemExit) { @task.invoke }
      assert_equal 1, raised.status
    end

    assert_includes out, "status=refused"
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end

  test "future season refuses with exit 1 and zero HTTP regardless of artifacts" do
    future = Time.zone.now.year + 1
    out, = capture_io do
      raised = assert_raises(SystemExit) { @task.invoke(future.to_s) }
      assert_equal 1, raised.status
    end

    assert_includes out, "status=refused"
    assert_includes out, future.to_s
    assert_not_requested(:get, /v3\.football\.api-sports\.io/)
  end
end

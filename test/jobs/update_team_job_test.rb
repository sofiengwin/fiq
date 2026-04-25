# frozen_string_literal: true

require "test_helper"

class UpdateTeamJobTest < ActiveSupport::TestCase
  setup do
    @country = Country.find_or_create_by!(name: "England")
    @team = FootballTeam.find_or_create_by!(external_id: "33") do |t|
      t.name = "Old Name"
      t.code = "OLD"
      t.country = @country
    end
  end

  test "calls UpdateTeam service with team" do
    VCR.use_cassette("update_team_33", record: :new_episodes) do
      UpdateTeamJob.perform_now(@team.id)

      @team.reload
      assert_equal "Manchester United", @team.name
    end
  end

  test "enqueues job in team_sync queue" do
    assert_equal "team_sync", UpdateTeamJob.new.queue_name
  end
end

# frozen_string_literal: true

require "test_helper"

class UpdateTeamTest < ActiveSupport::TestCase
  setup do
    @country = Country.find_or_create_by!(name: "England")
    @team = FootballTeam.find_or_create_by!(external_id: "33") do |t|
      t.name = "Old Name"
      t.code = "OLD"
      t.country = @country
    end
  end

  test "fetches and updates team data from API" do
    VCR.use_cassette("update_team_33", record: :new_episodes) do
      result = UpdateTeam.call(football_team: @team)

      assert_equal @team, result
      @team.reload
      assert_equal "Manchester United", @team.name
      assert_equal "MUN", @team.code
    end
  end

  test "raises ArgumentError when football_team has no external_id" do
    team_without_external_id = FootballTeam.create!(
      name: "No External ID",
      country: @country,
      external_id: nil
    )

    assert_raises(ArgumentError) do
      UpdateTeam.call(football_team: team_without_external_id)
    end
  end

  test "raises TeamNotFoundError for invalid external_id" do
    VCR.use_cassette("update_team_invalid", record: :new_episodes) do
      invalid_team = FootballTeam.create!(
        external_id: "999999999",
        name: "Invalid Team",
        country: @country
      )

      assert_raises(UpdateTeam::TeamNotFoundError) do
        UpdateTeam.call(football_team: invalid_team)
      end
    end
  end

  test "creates country if it does not exist" do
    VCR.use_cassette("update_team_33", record: :new_episodes) do
      @team.update!(country: Country.find_or_create_by!(name: "Unknown"))

      UpdateTeam.call(football_team: @team)

      @team.reload
      assert_equal "England", @team.country.name
    end
  end
end

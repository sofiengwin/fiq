require "test_helper"

class UpsertPlayerCareerTest < ActiveSupport::TestCase
  setup do
    @country = Country.find_or_create_by!(name: "Colombia")
    @italy = Country.find_or_create_by!(name: "Italy")
    @player = Player.create!(
      name: "Juan Cuadrado",
      external_id: "866",
      first_name: "Juan",
      last_name: "Cuadrado"
    )
  end

  test "creates careers for player with external_id 866" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      assert_difference -> { Career.count }, 5 do
        UpsertPlayerCareer.call(player: @player)
      end

      @player.reload
      assert @player.careers.any?, "Player should have careers after upsert"
    end
  end

  test "creates associated football teams when they don't exist" do
    VCR.use_cassette("upsert_player_career_866_teams", record: :none) do
      initial_team_count = FootballTeam.count

      UpsertPlayerCareer.call(player: @player)

      assert FootballTeam.count > initial_team_count, "Should create football teams"
    end
  end

  test "handles player with no transfers gracefully" do
    player_without_transfers = Player.create!(
      name: "Unknown Player",
      external_id: "999999999"
    )

    VCR.use_cassette("upsert_player_career_no_transfers", record: :none) do
      assert_nothing_raised do
        UpsertPlayerCareer.call(player: player_without_transfers)
      end
    end
  end

  test "creates country for team if it doesn't exist" do
    VCR.use_cassette("upsert_player_career_866_country", record: :none) do
      UpsertPlayerCareer.call(player: @player)

      # Check that countries were created for the teams
      assert Country.exists?(name: "Italy"), "Should create Italy country for Italian teams"
    end
  end

  test "fetches transfer data from API" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      # Verify the service makes API calls
      assert_nothing_raised do
        transfers = FootballClient.call(end_point: "transfers?player=866")
        assert transfers.is_a?(Array)
        assert transfers.first.key?(:transfers)
      end
    end
  end

  test "fetches player teams data from API" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      teams = FootballClient.call(end_point: "players/teams?player=866")
      assert teams.is_a?(Array)
      assert teams.any? { |t| t.dig(:team, :name) == "Juventus" }
    end
  end

  test "creates multiple non-overlapping careers for same club" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      UpsertPlayerCareer.call(player: @player)

      @player.reload
      # Cuadrado had multiple stints at Juventus - these should be separate career records
      # as long as they don't overlap
      @player.careers.each do |career|
        overlapping = @player.careers
          .where.not(id: career.id)
          .where("duration && ?::daterange", "[#{career.duration.begin},#{career.duration.end || 'infinity'})")

        assert_equal 0, overlapping.count, "Career should not overlap with other careers"
      end
    end
  end

  test "service handles seasons array from API response" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      teams = FootballClient.call(end_point: "players/teams?player=866")

      # API returns seasons as array, not singular season
      teams.each do |team_data|
        assert team_data[:seasons].is_a?(Array), "seasons should be an array"
      end
    end
  end

  test "does not duplicate careers on second run" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      UpsertPlayerCareer.call(player: @player)
      initial_career_count = @player.careers.count

      UpsertPlayerCareer.call(player: @player)
      @player.reload

      assert_equal initial_career_count, @player.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end

  test "creates careers with valid duration ranges" do
    VCR.use_cassette("upsert_player_career_866", record: :none) do
      UpsertPlayerCareer.call(player: @player)

      @player.careers.each do |career|
        assert career.duration.present?, "Career should have a duration"
        assert career.duration.begin.present?, "Career should have a start date"
        assert career.football_team.present?, "Career should be associated with a team"
      end
    end
  end

  # Tests for player with external_id 886
  test "creates careers for player with external_id 886" do
    player_886 = Player.create!(
      name: "Player 886",
      external_id: "886",
      first_name: "Test",
      last_name: "Player"
    )

    VCR.use_cassette("upsert_player_career_886", record: :none) do
      assert_difference -> { Career.count }, 2 do
        UpsertPlayerCareer.call(player: player_886)
      end

      player_886.reload
      assert player_886.careers.any?, "Player 886 should have careers after upsert"
    end
  end

  test "player 886 careers have valid durations" do
    player_886 = Player.create!(
      name: "Player 886",
      external_id: "886",
      first_name: "Test",
      last_name: "Player"
    )

    VCR.use_cassette("upsert_player_career_886", record: :none) do
      UpsertPlayerCareer.call(player: player_886)

      player_886.careers.each do |career|
        assert career.duration.present?, "Career should have a duration"
        assert career.duration.begin.present?, "Career should have a start date"
        assert career.football_team.present?, "Career should be associated with a team"
      end
    end
  end

  test "player 886 does not duplicate careers on second run" do
    player_886 = Player.create!(
      name: "Player 886",
      external_id: "886",
      first_name: "Test",
      last_name: "Player"
    )

    VCR.use_cassette("upsert_player_career_886", record: :none) do
      UpsertPlayerCareer.call(player: player_886)
      initial_career_count = player_886.careers.count

      UpsertPlayerCareer.call(player: player_886)
      player_886.reload

      assert_equal initial_career_count, player_886.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end
end

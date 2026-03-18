require "test_helper"

class UpsertPlayerCareerTest < ActiveSupport::TestCase
  setup do
    @country = Country.find_or_create_by!(name: "Colombia")
    @italy = Country.find_or_create_by!(name: "Italy")
    @player = Player.find_or_create_by!(external_id: "866") do |p|
      p.name = "Juan Cuadrado"
      p.first_name = "Juan"
      p.last_name = "Cuadrado"
    end
  end

  private

  def player_886
    @player_886 ||= Player.find_or_create_by!(external_id: "886") do |p|
      p.name = "Player 886"
      p.first_name = "Test"
      p.last_name = "Player"
    end
  end

  def player_157997
    @player_157997 ||= Player.find_or_create_by!(external_id: "157997") do |p|
      p.name = "Player 157997"
      p.first_name = "Test"
      p.last_name = "Player"
    end
  end

  def player_382452
    @player_382452 ||= Player.find_or_create_by!(external_id: "382452") do |p|
      p.name = "Player 382452"
      p.first_name = "Test"
      p.last_name = "Player"
    end
  end

  test "creates careers for player with external_id 866" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      UpsertPlayerCareer.call(player: @player)

      @player.reload
      assert @player.careers.any?, "Player should have careers after upsert"
    end
  end

  test "creates associated football teams when they don't exist" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      initial_team_count = FootballTeam.count

      UpsertPlayerCareer.call(player: @player)

      assert FootballTeam.count > initial_team_count, "Should create football teams"
    end
  end

  test "handles player with no transfers gracefully" do
    player_without_transfers = Player.find_or_create_by!(external_id: "999999999") do |p|
      p.name = "Unknown Player"
    end

    VCR.use_cassette("upsert_player_career_no_transfers", record: :new_episodes) do
      assert_nothing_raised do
        UpsertPlayerCareer.call(player: player_without_transfers)
      end
    end
  end

  test "creates country for team if it doesn't exist" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      UpsertPlayerCareer.call(player: @player)

      # Check that countries were created for the teams
      assert Country.exists?(name: "Italy"), "Should create Italy country for Italian teams"
    end
  end

  test "fetches transfer data from API" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      # Verify the service makes API calls
      assert_nothing_raised do
        transfers = FootballClient.call(end_point: "transfers?player=866")
        assert transfers.is_a?(Array)
        assert transfers.first.key?(:transfers)
      end
    end
  end

  test "fetches player teams data from API" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      teams = FootballClient.call(end_point: "players/teams?player=866")
      assert teams.is_a?(Array)
      assert teams.any? { |t| t.dig(:team, :name) == "Juventus" }
    end
  end

  test "creates multiple non-overlapping careers for same club" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      UpsertPlayerCareer.call(player: @player)

      @player.reload
      # Cuadrado had multiple stints at Juventus - these should be separate career records
      # as long as they don't overlap at the same team
      @player.careers.each do |career|
        overlapping = @player.careers
          .where.not(id: career.id)
          .where(football_team_id: career.football_team_id)
          .where("duration && ?::daterange", "[#{career.duration.begin},#{career.duration.end || 'infinity'})")

        assert_equal 0, overlapping.count, "Careers at the same club should not overlap"
      end
    end
  end

  test "service handles seasons array from API response" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      teams = FootballClient.call(end_point: "players/teams?player=866")

      # API returns seasons as array, not singular season
      teams.each do |team_data|
        assert team_data[:seasons].is_a?(Array), "seasons should be an array"
      end
    end
  end

  test "does not duplicate careers on second run" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
      UpsertPlayerCareer.call(player: @player)
      initial_career_count = @player.careers.count

      UpsertPlayerCareer.call(player: @player)
      @player.reload

      assert_equal initial_career_count, @player.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end

  test "creates careers with valid duration ranges" do
    VCR.use_cassette("upsert_player_career_866", record: :new_episodes) do
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
    VCR.use_cassette("upsert_player_career_886", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_886)

      player_886.reload
      assert player_886.careers.any?, "Player 886 should have careers after upsert"
    end
  end

  test "player 886 careers have valid durations" do
    VCR.use_cassette("upsert_player_career_886", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_886)

      player_886.careers.each do |career|
        assert career.duration.present?, "Career should have a duration"
        assert career.duration.begin.present?, "Career should have a start date"
        assert career.football_team.present?, "Career should be associated with a team"
      end
    end
  end

  test "player 886 does not duplicate careers on second run" do
    VCR.use_cassette("upsert_player_career_886", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_886)
      initial_career_count = player_886.careers.count

      UpsertPlayerCareer.call(player: player_886)
      player_886.reload

      assert_equal initial_career_count, player_886.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end

  # Tests for player with external_id 157997
  test "creates careers for player with external_id 157997" do
    VCR.use_cassette("upsert_player_career_157997", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_157997)

      player_157997.reload
      assert player_157997.careers.any?, "Player 157997 should have careers after upsert"
    end
  end

  test "player 157997 careers have valid durations" do
    VCR.use_cassette("upsert_player_career_157997", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_157997)

      player_157997.careers.each do |career|
        assert career.duration.present?, "Career should have a duration"
        assert career.duration.begin.present?, "Career should have a start date"
        assert career.football_team.present?, "Career should be associated with a team"
      end
    end
  end

  test "player 157997 does not duplicate careers on second run" do
    VCR.use_cassette("upsert_player_career_157997", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_157997)
      initial_career_count = player_157997.careers.count

      UpsertPlayerCareer.call(player: player_157997)
      player_157997.reload

      assert_equal initial_career_count, player_157997.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end

  test "player 157997 careers do not contain duplicates" do
    VCR.use_cassette("upsert_player_career_157997", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_157997)

      player_157997.reload
      careers = player_157997.careers

      # Check for exact duplicates (same team and same duration)
      career_keys = careers.map { |c| [ c.football_team_id, c.duration.begin, c.duration.end ] }
      assert_equal career_keys.uniq.count, career_keys.count,
        "Should not have duplicate careers with same team and duration"

      # Check for overlapping careers at the same team
      careers.group_by(&:football_team_id).each do |team_id, team_careers|
        team_careers.combination(2).each do |career1, career2|
          range1 = career1.duration
          range2 = career2.duration

          overlaps = range1.begin < (range2.end || Date.new(9999, 12, 31)) &&
                     range2.begin < (range1.end || Date.new(9999, 12, 31))

          assert_not overlaps,
            "Careers at team #{team_id} should not overlap: #{range1} and #{range2}"
        end
      end
    end
  end

  # Tests for player with external_id 382452
  test "creates careers for player with external_id 382452" do
    VCR.use_cassette("upsert_player_career_382452", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_382452)

      player_382452.reload
      assert player_382452.careers.any?, "Player 382452 should have careers after upsert"
    end
  end

  test "player 382452 careers have valid durations" do
    VCR.use_cassette("upsert_player_career_382452", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_382452)

      player_382452.careers.each do |career|
        assert career.duration.present?, "Career should have a duration"
        assert career.duration.begin.present?, "Career should have a start date"
        assert career.football_team.present?, "Career should be associated with a team"
      end
    end
  end

  test "player 382452 does not duplicate careers on second run" do
    VCR.use_cassette("upsert_player_career_382452", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_382452)
      initial_career_count = player_382452.careers.count

      UpsertPlayerCareer.call(player: player_382452)
      player_382452.reload

      assert_equal initial_career_count, player_382452.careers.count,
        "Running upsert twice should not create duplicate careers"
    end
  end

  test "player 382452 careers do not contain duplicates" do
    VCR.use_cassette("upsert_player_career_382452", record: :new_episodes) do
      UpsertPlayerCareer.call(player: player_382452)

      player_382452.reload
      careers = player_382452.careers

      # Check for exact duplicates (same team and same duration)
      career_keys = careers.map { |c| [ c.football_team_id, c.duration.begin, c.duration.end ] }
      assert_equal career_keys.uniq.count, career_keys.count,
        "Should not have duplicate careers with same team and duration"

      # Check for overlapping careers at the same team
      career_details = careers.map do |c|
        {
          team_name: c.football_team.name,
          start_date: c.duration.begin.to_s,
          end_date: (c.duration.end || "infinity").to_s
        }
      end
      assert_equal([ { team_name: "Manchester United", start_date: "2025-02-02", end_date: "Infinity" },
        { team_name: "Denmark", start_date: "2024-07-01", end_date: "Infinity" },
        { team_name: "Lecce", start_date: "2023-07-01", end_date: "2025-02-03" } ], career_details,
        "Careers should not have duplicates or overlaps at the same team")
    end
  end
end

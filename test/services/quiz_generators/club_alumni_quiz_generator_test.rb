# frozen_string_literal: true

require "test_helper"

module QuizGenerators
  class ClubAlumniQuizGeneratorTest < ActiveSupport::TestCase
    setup do
      @country = Country.find_or_create_by!(name: "England")
      @country2 = Country.find_or_create_by!(name: "Spain")

      @team = FootballTeam.create!(
        name: "Manchester United",
        country: @country,
        external_id: "mu_test"
      )

      @team2 = FootballTeam.create!(
        name: "Liverpool",
        country: @country,
        external_id: "lfc_test"
      )

      @team3 = FootballTeam.create!(
        name: "Chelsea",
        country: @country,
        external_id: "cfc_test"
      )

      @team4 = FootballTeam.create!(
        name: "Arsenal",
        country: @country,
        external_id: "afc_test"
      )

      # Create players with careers at @team
      @players = 6.times.map do |i|
        player = Player.create!(
          name: "Player #{i}",
          external_id: "player_test_#{i}"
        )
        Career.create!(
          player: player,
          football_team: @team,
          duration: Date.new(2020, 1, 1)..Date.new(2023, 1, 1),
          appearances: 50
        )
        player
      end
    end

    teardown do
      Career.delete_all
      Player.delete_all
      FootballTeam.delete_all
      Country.delete_all
    end

    test "returns nil when no team is provided and no suitable team exists" do
      Career.delete_all
      Player.delete_all

      result = ClubAlumniQuizGenerator.call(player_count: 10)

      assert_nil result
    end

    test "generates quiz with correct structure" do
      result = ClubAlumniQuizGenerator.call(player_count: 4)
      binding.irb

      assert_not_nil result
      assert_equal :club_alumni, result[:type]
      assert_equal "Which club did ALL of these players play for?", result[:prompt]
      assert_equal 4, result[:players].size
      assert_includes result[:options], @team
      assert_equal @team.id, result[:correct_answer]
      assert_equal @team.name, result[:answer_hint]
    end

    test "respects player_count parameter" do
      result = ClubAlumniQuizGenerator.call(player_count: 5)

      assert_not_nil result
      assert_equal 5, result[:players].size
      assert_equal 5, result[:config][:player_count]
    end

    test "clamps player_count to valid range" do
      result_low = ClubAlumniQuizGenerator.call(player_count: 2)
      result_high = ClubAlumniQuizGenerator.call(player_count: 10)

      assert_equal 4, result_low[:config][:player_count] if result_low
      assert_equal 6, result_high[:config][:player_count] if result_high
    end

    test "uses provided team when specified" do
      result = ClubAlumniQuizGenerator.call(team: @team, player_count: 4)

      assert_not_nil result
      assert_equal @team.id, result[:correct_answer]
    end

    test "includes decoy teams in options" do
      result = ClubAlumniQuizGenerator.call(player_count: 4)

      assert_not_nil result
      assert result[:options].size >= 2, "Should have at least correct team and one decoy"
      assert result[:options].size <= 4, "Should have at most 4 options"
    end

    test "all players in result belong to the correct team" do
      result = ClubAlumniQuizGenerator.call(player_count: 4)

      assert_not_nil result
      result[:players].each do |player|
        team_ids = player.careers.pluck(:football_team_id)
        assert_includes team_ids, result[:correct_answer],
          "Player #{player.name} should have played for the correct team"
      end
    end

    test "excludes specified team ids" do
      result = ClubAlumniQuizGenerator.call(
        player_count: 4,
        exclude_team_ids: [ @team.id ]
      )

      # Since @team is the only team with enough players, result should be nil
      assert_nil result
    end

    test "returns nil when team has insufficient players" do
      # Create a team with only 2 players
      small_team = FootballTeam.create!(
        name: "Small Team",
        country: @country,
        external_id: "small_test"
      )

      2.times do |i|
        player = Player.create!(
          name: "Small Player #{i}",
          external_id: "small_player_#{i}"
        )
        Career.create!(
          player: player,
          football_team: small_team,
          duration: Date.new(2020, 1, 1)..Date.new(2023, 1, 1)
        )
      end

      result = ClubAlumniQuizGenerator.call(team: small_team, player_count: 4)

      assert_nil result
    end

    test "config includes player_count" do
      result = ClubAlumniQuizGenerator.call(player_count: 5)

      assert_not_nil result
      assert_equal 5, result[:config][:player_count]
    end
  end
end

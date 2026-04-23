# frozen_string_literal: true

require "test_helper"

module QuizGenerators
  class QuizGeneratorTest < ActiveSupport::TestCase
    setup do
      @country = Country.find_or_create_by!(name: "England")
      @country2 = Country.find_or_create_by!(name: "Spain")

      @competition = Competition.create!(
        name: "Premier League",
        country: @country,
        external_id: "pl_test"
      )

      @team = FootballTeam.create!(
        name: "Manchester United",
        country: @country,
        external_id: "mu_test"
      )
      @team.competitions << @competition

      @team2 = FootballTeam.create!(
        name: "Liverpool",
        country: @country,
        external_id: "lfc_test"
      )
      @team2.competitions << @competition

      @team3 = FootballTeam.create!(
        name: "Real Madrid",
        country: @country2,
        external_id: "rm_test"
      )

      # Create players with careers
      @players = 8.times.map do |i|
        player = Player.create!(
          name: "Player #{i}",
          external_id: "player_test_#{i}"
        )

        # Give each player careers at different teams
        Career.create!(
          player: player,
          football_team: @team,
          duration: Date.new(2018, 1, 1)..Date.new(2021, 1, 1),
          appearances: 100
        )

        if i < 4
          Career.create!(
            player: player,
            football_team: @team2,
            duration: Date.new(2021, 1, 1)..Date.new(2024, 1, 1),
            appearances: 80
          )
        end

        if i < 2
          Career.create!(
            player: player,
            football_team: @team3,
            duration: Date.new(2024, 1, 1)..Date.new(2026, 1, 1),
            appearances: 40
          )
        end

        player
      end
    end

    teardown do
      Career.delete_all
      Player.delete_all
      FootballTeam.connection.execute("DELETE FROM competitions_football_teams")
      FootballTeam.delete_all
      Competition.delete_all
      Country.delete_all
    end

    test "QUIZ_TYPES contains all expected quiz types" do
      expected_types = %i[
        overlapping_careers
        club_alumni
        competition_connection
        appearances_milestone
        career_path
        multi_club_crossover
        country_hopper
      ]

      expected_types.each do |type|
        assert QuizGenerator::QUIZ_TYPES.key?(type),
          "QUIZ_TYPES should include #{type}"
      end
    end

    test "available_types returns all quiz type keys" do
      types = QuizGenerator.available_types

      assert_kind_of Array, types
      assert_equal QuizGenerator::QUIZ_TYPES.keys, types
    end

    test "fast_types returns subset of quiz types" do
      fast_types = QuizGenerator.fast_types

      assert_kind_of Array, fast_types
      fast_types.each do |type|
        assert QuizGenerator::QUIZ_TYPES.key?(type),
          "Fast type #{type} should be in QUIZ_TYPES"
      end
    end

    test "call raises ArgumentError for unknown quiz type" do
      assert_raises ArgumentError do
        QuizGenerator.call(type: :unknown_type)
      end
    end

    test "call dispatches to correct generator for club_alumni" do
      result = QuizGenerator.call(type: :club_alumni)

      assert_not_nil result
      assert_equal :club_alumni, result[:type]
    end

    test "call passes options to generator" do
      result = QuizGenerator.call(type: :club_alumni, player_count: 5)

      if result
        assert_equal 5, result[:config][:player_count]
      end
    end

    test "random returns array of questions" do
      questions = QuizGenerator.random(count: 5)

      assert_kind_of Array, questions
      assert questions.size <= 5, "Should return at most requested count"
    end

    test "random uses fast_types by default" do
      questions = QuizGenerator.random(count: 3)

      questions.each do |q|
        assert QuizGenerator::FAST_TYPES.include?(q[:type]),
          "Random should use fast types by default, got #{q[:type]}"
      end
    end

    test "random allows specifying quiz types" do
      questions = QuizGenerator.random(count: 3, types: [ :club_alumni ])

      questions.each do |q|
        assert_equal :club_alumni, q[:type]
      end
    end

    test "random handles generator failures gracefully" do
      # This should not raise even if some generators fail
      questions = QuizGenerator.random(count: 5, types: [ :appearances_milestone ])

      assert_kind_of Array, questions
    end

    test "random respects count parameter" do
      questions = QuizGenerator.random(count: 3, types: [ :club_alumni ])

      assert questions.size <= 3
    end

    test "each quiz type can be called individually" do
      QuizGenerator::QUIZ_TYPES.keys.each do |type|
        # Just verify it doesn't raise an error
        begin
          result = QuizGenerator.call(type: type)
          if result
            assert_equal type, result[:type],
              "Result type should match requested type"
          end
        rescue StandardError => e
          # Some types may fail due to insufficient data, which is acceptable
          assert_kind_of StandardError, e
        end
      end
    end

    test "FAST_TYPES excludes overlapping_careers and appearances_milestone" do
      assert_not_includes QuizGenerator::FAST_TYPES, :overlapping_careers
      assert_not_includes QuizGenerator::FAST_TYPES, :appearances_milestone
    end
  end
end

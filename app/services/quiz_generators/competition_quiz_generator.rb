# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions about players who have played in specific competitions.
  #
  # Example:
  #   QuizGenerators::CompetitionQuizGenerator.call(player_count: 5)
  #
  class CompetitionQuizGenerator < ApplicationService
    MIN_PLAYER_COUNT = 4
    MAX_PLAYER_COUNT = 6

    def initialize(competition: nil, player_count: 5, exclude_competition_ids: [])
      @competition = competition
      @player_count = player_count.clamp(MIN_PLAYER_COUNT, MAX_PLAYER_COUNT)
      @exclude_competition_ids = exclude_competition_ids
    end

    def call
      competition = @competition || find_suitable_competition
      return nil unless competition

      correct_players = find_players_in_competition(competition)
      return nil if correct_players.size < @player_count

      decoy_players = find_players_not_in_competition(competition, correct_players)
      return nil if decoy_players.size < @player_count

      {
        type: :competition_connection,
        prompt: "Select all players who have played in the #{competition.name}",
        competition: competition,
        options: (correct_players + decoy_players).shuffle,
        correct_answer: correct_players.map(&:id),
        config: {
          player_count: @player_count
        },
        answer_hint: "Players who played in #{competition.name}"
      }
    end

    private

    def find_suitable_competition
      query = Competition
              .joins(football_teams: :players)
              .group("competitions.id")
              .having("COUNT(DISTINCT players.id) >= ?", @player_count * 2)
              .order(Arel.sql("COUNT(DISTINCT players.id) DESC, RANDOM()"))

      query = query.where.not(id: @exclude_competition_ids) if @exclude_competition_ids.any?

      query.first
    end

    def find_players_in_competition(competition)
      # Use subquery to avoid DISTINCT + ORDER BY RANDOM() conflict in PostgreSQL
      player_ids = Player
                   .joins(careers: { football_team: :competitions })
                   .where(competitions: { id: competition.id })
                   .distinct
                   .pluck(:id)
                   .sample(@player_count)

      Player.where(id: player_ids).to_a
    end

    def find_players_not_in_competition(competition, exclude_players)
      exclude_ids = exclude_players.map(&:id)

      # Find players who played in OTHER competitions
      # Use subquery to avoid DISTINCT + ORDER BY RANDOM() conflict
      player_ids = Player
                   .joins(careers: { football_team: :competitions })
                   .where.not(competitions: { id: competition.id })
                   .where.not(id: exclude_ids)
                   .distinct
                   .pluck(:id)
                   .sample(@player_count)

      Player.where(id: player_ids).to_a
    end
  end
end

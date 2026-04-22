# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions where users match players to their career paths.
  #
  # Example:
  #   QuizGenerators::CareerPathQuizGenerator.call(min_clubs: 3)
  #
  class CareerPathQuizGenerator < ApplicationService
    MIN_CLUBS = 3
    MAX_CLUBS = 6

    def initialize(min_clubs: 3, exclude_player_ids: [])
      @min_clubs = min_clubs.clamp(MIN_CLUBS, MAX_CLUBS)
      @exclude_player_ids = exclude_player_ids
    end

    def call
      player = find_player_with_career_path
      return nil unless player

      path = build_career_path(player)
      return nil if path.empty?

      decoy_players = find_decoy_players(player)
      return nil if decoy_players.size < 3

      {
        type: :career_path,
        prompt: "Which player had this career path?",
        path_display: path.join(" → "),
        path: path,
        options: ([ player ] + decoy_players).shuffle,
        correct_answer: player.id,
        config: {
          min_clubs: @min_clubs
        },
        answer_hint: player.name
      }
    end

    private

    def find_player_with_career_path
      query = Player
              .joins(:careers)
              .group("players.id")
              .having("COUNT(DISTINCT careers.football_team_id) >= ?", @min_clubs)
              .order(Arel.sql("RANDOM()"))

      query = query.where.not(id: @exclude_player_ids) if @exclude_player_ids.any?

      query.first
    end

    def build_career_path(player)
      player.careers
            .includes(:football_team)
            .order(Arel.sql("LOWER(duration)"))
            .map { |c| c.football_team.name }
    end

    def find_decoy_players(correct_player)
      # Find players with similar number of clubs to make it harder
      Player
        .joins(:careers)
        .where.not(id: correct_player.id)
        .group("players.id")
        .having("COUNT(DISTINCT careers.football_team_id) >= ?", @min_clubs)
        .order(Arel.sql("RANDOM()"))
        .limit(3)
        .to_a
    end
  end
end

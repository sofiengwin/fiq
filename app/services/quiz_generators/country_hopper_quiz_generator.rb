# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions about players who played in multiple countries.
  #
  # Example:
  #   QuizGenerators::CountryHopperQuizGenerator.call(min_countries: 3)
  #
  class CountryHopperQuizGenerator < ApplicationService
    MIN_COUNTRIES = 2
    MAX_COUNTRIES = 5

    def initialize(min_countries: 3, exclude_player_ids: [])
      @min_countries = min_countries.clamp(MIN_COUNTRIES, MAX_COUNTRIES)
      @exclude_player_ids = exclude_player_ids
    end

    def call
      player = find_player_with_multiple_countries
      return nil unless player

      countries = get_countries_for_player(player)
      return nil if countries.size < @min_countries

      decoy_players = find_decoy_players(player)
      return nil if decoy_players.size < 3

      {
        type: :country_hopper,
        prompt: "Which player played in #{countries.to_sentence}?",
        countries: countries,
        options: ([ player ] + decoy_players).shuffle,
        correct_answer: player.id,
        config: {
          min_countries: @min_countries
        },
        answer_hint: player.name
      }
    end

    private

    def find_player_with_multiple_countries
      query = Player
              .joins(careers: { football_team: :country })
              .group("players.id")
              .having("COUNT(DISTINCT countries.id) >= ?", @min_countries)
              .order(Arel.sql("RANDOM()"))

      query = query.where.not(id: @exclude_player_ids) if @exclude_player_ids.any?

      query.first
    end

    def get_countries_for_player(player)
      player.careers
            .joins(football_team: :country)
            .pluck(Arel.sql("DISTINCT countries.name"))
    end

    def find_decoy_players(correct_player)
      # Find other players who also played in multiple countries
      # to make the question more challenging
      Player
        .joins(careers: { football_team: :country })
        .where.not(id: correct_player.id)
        .group("players.id")
        .having("COUNT(DISTINCT countries.id) >= ?", @min_countries)
        .order(Arel.sql("RANDOM()"))
        .limit(3)
        .to_a
    end
  end
end

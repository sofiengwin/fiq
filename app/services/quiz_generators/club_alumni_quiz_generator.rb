# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions for finding players who all played for the same club
  # (but not necessarily at the same time).
  #
  # Example:
  #   QuizGenerators::ClubAlumniQuizGenerator.call(player_count: 5)
  #
  class ClubAlumniQuizGenerator < ApplicationService
    MIN_PLAYER_COUNT = 4
    MAX_PLAYER_COUNT = 6

    def initialize(team: nil, player_count: 5, exclude_team_ids: [])
      @team = team
      @player_count = player_count.clamp(MIN_PLAYER_COUNT, MAX_PLAYER_COUNT)
      @exclude_team_ids = exclude_team_ids
    end

    def call
      team = @team || find_suitable_team
      return nil unless team

      # Use subquery to avoid DISTINCT + ORDER BY RANDOM() conflict in PostgreSQL
      player_ids = team.players.distinct.pluck(:id).sample(@player_count)
      players = Player.where(id: player_ids)
      return nil if players.size < @player_count

      decoy_teams = find_decoy_teams(team)

      {
        type: :club_alumni,
        prompt: "Which club did ALL of these players play for?",
        players: players.to_a,
        options: ([ team ] + decoy_teams).shuffle,
        correct_answer: team.id,
        config: {
          player_count: @player_count
        },
        answer_hint: team.name
      }
    end

    private

    def find_suitable_team
      query = FootballTeam.joins(:careers)
                          .group("football_teams.id")
                          .having("COUNT(DISTINCT careers.player_id) >= ?", @player_count)
                          .order(Arel.sql("COUNT(DISTINCT careers.player_id) DESC, RANDOM()"))

      query = query.where.not(id: @exclude_team_ids) if @exclude_team_ids.any?

      query.first
    end

    def find_decoy_teams(correct_team)
      # Find teams that are similar (same country/competition) but don't have all the players
      FootballTeam
        .where.not(id: correct_team.id)
        .where(country_id: correct_team.country_id)
        .order(Arel.sql("RANDOM()"))
        .limit(3)
        .to_a
        .tap do |teams|
          # If not enough teams in same country, add random teams
          if teams.size < 3
            additional = FootballTeam
                         .where.not(id: [ correct_team.id ] + teams.map(&:id))
                         .order(Arel.sql("RANDOM()"))
                         .limit(3 - teams.size)
            teams.concat(additional)
          end
        end
    end
  end
end

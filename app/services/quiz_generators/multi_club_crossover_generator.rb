# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions about players who share multiple clubs in common.
  #
  # Example:
  #   QuizGenerators::MultiClubCrossoverGenerator.call(shared_clubs: 2, player_count: 4)
  #
  class MultiClubCrossoverGenerator < ApplicationService
    MIN_SHARED_CLUBS = 2
    MAX_SHARED_CLUBS = 3
    MIN_PLAYER_COUNT = 2
    MAX_PLAYER_COUNT = 4

    def initialize(shared_clubs: 2, player_count: 2, exclude_player_ids: [])
      @shared_clubs = shared_clubs.clamp(MIN_SHARED_CLUBS, MAX_SHARED_CLUBS)
      @player_count = player_count.clamp(MIN_PLAYER_COUNT, MAX_PLAYER_COUNT)
      @exclude_player_ids = exclude_player_ids
    end

    def call
      result = find_players_with_shared_clubs
      return nil unless result

      players, shared_teams = result

      decoy_teams = find_decoy_teams(shared_teams)

      {
        type: :multi_club_crossover,
        prompt: "These #{players.size} players all played for the same #{@shared_clubs} clubs. Which clubs?",
        players: players,
        club_options: (shared_teams + decoy_teams).shuffle,
        correct_clubs: shared_teams.map(&:id),
        config: {
          shared_clubs: @shared_clubs,
          player_count: @player_count
        },
        answer_hint: shared_teams.map(&:name).join(" and ")
      }
    end

    private

    def find_players_with_shared_clubs
      # Get players with their team IDs as arrays
      players_with_teams = Player
                           .joins(:careers)
                           .select("players.id, players.name, ARRAY_AGG(DISTINCT careers.football_team_id ORDER BY careers.football_team_id) as team_ids")
                           .group("players.id, players.name")
                           .having("COUNT(DISTINCT careers.football_team_id) >= ?", @shared_clubs)

      players_with_teams = players_with_teams.where.not(id: @exclude_player_ids) if @exclude_player_ids.any?

      # Convert to array and find pairs with shared clubs
      all_players = players_with_teams.to_a
      return nil if all_players.size < @player_count

      # Find groups of players who share N clubs
      find_matching_player_group(all_players)
    end

    def find_matching_player_group(all_players)
      # Try to find a pair/group of players sharing exactly @shared_clubs clubs
      all_players.combination(@player_count).each do |player_group|
        # Find intersection of all players' teams
        team_id_sets = player_group.map { |p| p.team_ids.to_a.to_set }
        common_team_ids = team_id_sets.reduce(&:&)

        if common_team_ids.size >= @shared_clubs
          shared_team_ids = common_team_ids.to_a.take(@shared_clubs)
          shared_teams = FootballTeam.where(id: shared_team_ids).to_a

          # Reload full player objects
          players = Player.where(id: player_group.map(&:id)).to_a

          return [ players, shared_teams ]
        end
      end

      nil
    end

    def find_decoy_teams(correct_teams)
      correct_team_ids = correct_teams.map(&:id)

      FootballTeam
        .where.not(id: correct_team_ids)
        .order(Arel.sql("RANDOM()"))
        .limit(4 - correct_teams.size)
        .to_a
    end
  end
end

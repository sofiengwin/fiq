# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions for finding players who played together
  # at the same club during overlapping time periods.
  #
  # Example:
  #   QuizGenerators::TeammatesQuizGenerator.call(group_size: 5, min_overlap_years: 2)
  #
  class TeammatesQuizGenerator < ApplicationService
    MIN_GROUP_SIZE = 4
    MAX_GROUP_SIZE = 6
    MIN_OVERLAP_YEARS = 1
    MAX_OVERLAP_YEARS = 4

    def initialize(difficulty: :medium, group_size: nil, min_overlap_years: nil, exclude_player_ids: [])
      preset = TeammatesQuiz.preset_for(difficulty)

      @group_size = (group_size || preset[:group_size]).clamp(MIN_GROUP_SIZE, MAX_GROUP_SIZE)
      @min_overlap_years = (min_overlap_years || preset[:min_overlap_years]).clamp(MIN_OVERLAP_YEARS, MAX_OVERLAP_YEARS)
      @min_overlap_days = @min_overlap_years * 365
      @exclude_player_ids = exclude_player_ids
    end

    def call
      team = find_team_with_overlapping_players
      return nil unless team

      players = find_overlapping_players_at_team(team)
      return nil if players.size < @group_size

      {
        type: :overlapping_careers,
        prompt: "Select the #{@group_size} players who played together at the same club (for at least #{@min_overlap_years} year(s))",
        players: players,
        common_team: team,
        correct_answer: players.map(&:id),
        config: {
          group_size: @group_size,
          min_overlap_years: @min_overlap_years
        },
        answer_hint: "All played together at #{team.name} for at least #{@min_overlap_years} year(s)"
      }
    end

    private

    def find_team_with_overlapping_players
      # Find teams with many players who have overlapping careers
      # Just check for overlap, not duration - we'll filter by duration in Ruby
      subquery = <<-SQL
        SELECT c1.football_team_id, COUNT(DISTINCT c1.player_id) as overlap_count
        FROM careers c1
        INNER JOIN careers c2
          ON c1.football_team_id = c2.football_team_id
          AND c1.player_id < c2.player_id
          AND c1.duration && c2.duration
          AND NOT upper_inf(c1.duration) AND NOT upper_inf(c2.duration)
        WHERE c1.duration IS NOT NULL AND c2.duration IS NOT NULL
        GROUP BY c1.football_team_id
        HAVING COUNT(DISTINCT c1.player_id) >= #{@group_size * 2}
      SQL

      FootballTeam
        .joins("INNER JOIN (#{subquery}) team_overlaps ON football_teams.id = team_overlaps.football_team_id")
        .order(Arel.sql("team_overlaps.overlap_count DESC, RANDOM()"))
        .limit(10) # Get top 10 teams and check each
        .to_a
        .find { |team| has_enough_overlapping_players?(team) }
    end

    def has_enough_overlapping_players?(team)
      careers = Career.where(football_team_id: team.id)
                      .where.not(duration: nil)
                      .where("NOT upper_inf(duration)")
                      .includes(:player).to_a

      graph = build_overlap_graph(careers)
      cliques = find_cliques(graph, @group_size)
      cliques.any?
    end

    def find_overlapping_players_at_team(team)
      # Get all players at this team with finite duration data
      base_query = Career.where(football_team_id: team.id)
                         .where.not(duration: nil)
                         .where("NOT upper_inf(duration)")

      base_query = base_query.where.not(player_id: @exclude_player_ids) if @exclude_player_ids.any?

      careers = base_query.includes(:player).to_a

      # Find a clique of players who all overlap with each other
      find_overlapping_clique(careers, @group_size)
    end

    def find_overlapping_clique(careers, target_size)
      # Build adjacency graph of overlapping players
      graph = build_overlap_graph(careers)

      # Find cliques using backtracking
      cliques = find_cliques(graph, target_size)

      return [] if cliques.empty?

      # Return players from the first valid clique
      clique_player_ids = cliques.sample
      Player.where(id: clique_player_ids).to_a
    end

    def build_overlap_graph(careers)
      graph = Hash.new { |h, k| h[k] = Set.new }

      careers.combination(2).each do |c1, c2|
        next unless careers_overlap?(c1, c2)

        graph[c1.player_id].add(c2.player_id)
        graph[c2.player_id].add(c1.player_id)
      end

      graph
    end

    def careers_overlap?(c1, c2)
      return false unless c1.duration && c2.duration
      return false unless c1.duration.overlaps?(c2.duration)

      # Skip infinite bounds - they can't be subtracted
      return false if c1.duration.begin.nil? || c2.duration.begin.nil?
      return false if c1.duration.end.nil? || c2.duration.end.nil?
      return false if c1.duration.end.is_a?(Float) || c2.duration.end.is_a?(Float)

      overlap_start = [ c1.duration.begin, c2.duration.begin ].max
      overlap_end = [ c1.duration.end, c2.duration.end ].min

      (overlap_end - overlap_start).to_i >= @min_overlap_days
    end

    def find_cliques(graph, min_size)
      cliques = []
      nodes = graph.keys

      return cliques if nodes.size < min_size

      # Simple greedy clique finding for small graphs
      nodes.each do |start_node|
        clique = [ start_node ]
        candidates = graph[start_node].to_a

        candidates.each do |candidate|
          if clique.all? { |member| graph[member].include?(candidate) }
            clique << candidate
          end
          break if clique.size >= min_size
        end

        cliques << clique if clique.size >= min_size
      end

      cliques
    end
  end
end

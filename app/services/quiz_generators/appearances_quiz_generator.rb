# frozen_string_literal: true

module QuizGenerators
  # Generates quiz questions about players who reached appearance milestones.
  #
  # Example:
  #   QuizGenerators::AppearancesQuizGenerator.call(threshold: 100, player_count: 5)
  #
  class AppearancesQuizGenerator < ApplicationService
    MIN_PLAYER_COUNT = 4
    MAX_PLAYER_COUNT = 6
    DEFAULT_THRESHOLD = 100

    THRESHOLDS = {
      easy: 50,
      medium: 100,
      hard: 200,
      expert: 300
    }.freeze

    def initialize(threshold: DEFAULT_THRESHOLD, player_count: 5, difficulty: nil)
      @threshold = difficulty ? THRESHOLDS.fetch(difficulty.to_sym, DEFAULT_THRESHOLD) : threshold
      @player_count = player_count.clamp(MIN_PLAYER_COUNT, MAX_PLAYER_COUNT)
    end

    def call
      correct_players = find_players_with_high_appearances
      return nil if correct_players.size < @player_count

      decoy_players = find_players_without_high_appearances(correct_players)
      return nil if decoy_players.size < @player_count

      {
        type: :appearances_milestone,
        prompt: "Select all players who made #{@threshold}+ appearances at a single club",
        options: (correct_players + decoy_players).shuffle,
        correct_answer: correct_players.map(&:id),
        config: {
          threshold: @threshold,
          player_count: @player_count
        },
        answer_hint: "Players with #{@threshold}+ appearances at one club"
      }
    end

    private

    def find_players_with_high_appearances
      # Use subquery to avoid DISTINCT + ORDER BY RANDOM() conflict in PostgreSQL
      player_ids = Player
                   .joins(:careers)
                   .where("careers.appearances >= ?", @threshold)
                   .distinct
                   .pluck(:id)
                   .sample(@player_count)

      Player.where(id: player_ids).to_a
    end

    def find_players_without_high_appearances(exclude_players)
      exclude_ids = exclude_players.map(&:id)

      player_ids = Player
                   .joins(:careers)
                   .where.not(id: exclude_ids)
                   .group("players.id")
                   .having("MAX(careers.appearances) < ?", @threshold)
                   .having("MAX(careers.appearances) > 0")
                   .pluck(:id)
                   .sample(@player_count)

      Player.where(id: player_ids).to_a
    end
  end
end

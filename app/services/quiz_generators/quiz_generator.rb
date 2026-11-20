# frozen_string_literal: true

module QuizGenerators
  # Unified quiz generator that dispatches to specific quiz type generators.
  #
  # Example:
  #   QuizGenerators::QuizGenerator.call(type: :overlapping_careers, group_size: 5)
  #   QuizGenerators::QuizGenerator.random
  #   QuizGenerators::QuizGenerator.random(types: [:club_alumni, :career_path])
  #
  class QuizGenerator < ApplicationService
    QUIZ_TYPES = {
      overlapping_careers: TeammatesQuizGenerator,
      club_alumni: ClubAlumniQuizGenerator,
      competition_connection: CompetitionQuizGenerator,
      appearances_milestone: AppearancesQuizGenerator,
      career_path: CareerPathQuizGenerator,
      multi_club_crossover: MultiClubCrossoverGenerator,
      country_hopper: CountryHopperQuizGenerator
    }.freeze

    # Fast types that don't require complex overlap calculations
    FAST_TYPES = %i[
      club_alumni
      competition_connection
      career_path
      multi_club_crossover
      country_hopper
    ].freeze

    class << self
      def random(count: 20, types: FAST_TYPES, **options)
        require "set" unless defined?(Set)
        questions = []
        seen = Set.new
        used_team_ids = []
        used_player_ids = []
        used_competition_ids = []
        attempts = 0
        max_attempts = count * 10 + 10 # Allow retries for dupes/failed generations
        allowed_types = Array(types) & QUIZ_TYPES.keys

        while questions.size < count && attempts < max_attempts
          attempts += 1
          type = allowed_types.sample

          begin
            call_options = with_excludes(type, options, used_team_ids, used_player_ids, used_competition_ids)
            result = new(type: type, **call_options).call
            next unless result

            key = dedupe_key(result)
            next if seen.include?(key)

            seen << key
            questions << result
            record_used_ids(result, used_team_ids, used_player_ids, used_competition_ids)
          rescue StandardError
            # Skip failed generations and try again
            next
          end
        end

        questions
      end

      def available_types
        QUIZ_TYPES.keys
      end

      def fast_types
        FAST_TYPES
      end

      private

      # Merge already-used IDs into the exclude list the target generator
      # understands. Generators without an exclude param get options untouched.
      def with_excludes(type, options, used_team_ids, used_player_ids, used_competition_ids)
        case type.to_sym
        when :club_alumni
          options.merge(exclude_team_ids: Array(options[:exclude_team_ids]) | used_team_ids)
        when :career_path, :country_hopper, :overlapping_careers, :multi_club_crossover
          options.merge(exclude_player_ids: Array(options[:exclude_player_ids]) | used_player_ids)
        when :competition_connection
          options.merge(exclude_competition_ids: Array(options[:exclude_competition_ids]) | used_competition_ids)
        else
          options
        end
      end

      def extract_id(obj)
        if obj.respond_to?(:id)
          obj.id
        elsif obj.is_a?(Hash)
          obj[:id] || obj["id"]
        else
          obj
        end
      end

      # Same answer + same subjects = same question, even with different decoys.
      def dedupe_key(result)
        type = result[:type].to_s
        correct = Array(result[:correct_answer] || result[:correct_clubs]).map { |id| extract_id(id).to_i }.sort
        players = Array(result[:players]).map { |p| extract_id(p).to_i }.sort
        competition = result[:competition] ? extract_id(result[:competition]).to_i : 0
        team = result[:common_team] ? extract_id(result[:common_team]).to_i : 0
        [ type, correct, players, competition, team, result[:prompt].to_s ]
      end

      def record_used_ids(result, used_team_ids, used_player_ids, used_competition_ids)
        case result[:type].to_sym
        when :club_alumni
          used_team_ids << extract_id(result[:correct_answer]).to_i
        when :multi_club_crossover
          Array(result[:correct_answer] || result[:correct_clubs]).each do |id|
            used_team_ids << extract_id(id).to_i
          end
        when :competition_connection
          used_competition_ids << extract_id(result[:competition]).to_i if result[:competition]
        when :overlapping_careers
          used_team_ids << extract_id(result[:common_team]).to_i if result[:common_team]
        end
        Array(result[:players]).each do |p|
          pid = extract_id(p).to_i
          used_player_ids << pid unless pid.zero?
        end
        # Single-player answer types carry the answer only in correct_answer.
        if %i[career_path country_hopper].include?(result[:type].to_sym)
          pid = extract_id(result[:correct_answer]).to_i
          used_player_ids << pid unless pid.zero?
        end
      end
    end

    def initialize(type:, **options)
      @type = type.to_sym
      @options = options
    end

    def call
      generator_class = QUIZ_TYPES[@type]
      raise ArgumentError, "Unknown quiz type: #{@type}. Available types: #{QUIZ_TYPES.keys.join(', ')}" unless generator_class

      generator_class.call(**@options)
    end
  end
end

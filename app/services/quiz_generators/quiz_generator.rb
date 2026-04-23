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
        questions = []
        attempts = 0
        max_attempts = count * 3 # Allow retries for failed generations
        allowed_types = Array(types) & QUIZ_TYPES.keys

        while questions.size < count && attempts < max_attempts
          attempts += 1
          type = allowed_types.sample

          begin
            result = new(type: type, **options).call
            questions << result if result
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

# frozen_string_literal: true

module QuizGenerators
  # Unified quiz generator that dispatches to specific quiz type generators.
  #
  # Example:
  #   QuizGenerators::QuizGenerator.call(type: :overlapping_careers, group_size: 5)
  #   QuizGenerators::QuizGenerator.random
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

    class << self
      def random(**options)
        type = QUIZ_TYPES.keys.sample
        new(type: type, **options).call
      end

      def available_types
        QUIZ_TYPES.keys
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

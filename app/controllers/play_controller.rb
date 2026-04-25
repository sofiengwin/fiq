# frozen_string_literal: true

class PlayController < ApplicationController
  allow_unauthenticated_access
  before_action :set_play_session, only: %i[question answer results destroy]

  # GET /play - Select quiz type
  def index
    @quiz_types = quiz_type_options
  end

  # POST /play - Start generated quiz
  def create
    # End any existing active game
    PlaySession.active.where(session_id: browser_session_id).destroy_all

    questions = generate_questions
    return redirect_to play_path, alert: "Could not generate questions. Please try again." if questions.empty?

    # Store full question data in database - no size limits!
    play_session = PlaySession.create!(
      session_id: browser_session_id,
      user: Current.user,
      quiz_type: params[:quiz_type] || "random",
      questions: serialize_questions(questions),
      started_at: Time.current
    )

    # Store the play session id in browser session for quick lookup
    session[:play_session_id] = play_session.id

    redirect_to play_question_path
  end

  # GET /play/question - Show current question
  def question
    redirect_to play_path and return unless @play_session&.game_active?

    @question = @play_session.current_question
    @progress = @play_session.progress
  end

  # POST /play/answer - Submit answer
  def answer
    redirect_to play_path and return unless @play_session&.game_active?

    @play_session.process_answer!(params[:selected_ids])

    if @play_session.game_complete?
      redirect_to play_results_path
    else
      redirect_to play_question_path
    end
  end

  # GET /play/results - Show final results
  def results
    redirect_to play_path and return unless @play_session

    @total_questions = @play_session.questions.length
    @correct_count = @play_session.correct_count
    @percentage = @play_session.percentage
    @total_score = @play_session.total_score
    @responses = @play_session.responses_with_questions
  end

  # DELETE /play - Quit game
  def destroy
    @play_session&.update(completed_at: Time.current)
    session.delete(:play_session_id)
    redirect_to play_path, notice: "Game ended."
  end

  private

  def set_play_session
    @play_session = PlaySession.find_by(id: session[:play_session_id])

    # Fallback: find by browser session if ID not in session
    @play_session ||= PlaySession.find_active_for(browser_session_id)

    # Store ID in session if found
    session[:play_session_id] = @play_session.id if @play_session
  end

  def browser_session_id
    session.id.to_s.presence || session[:_csrf_token] || SecureRandom.hex(16).tap { |id| session[:browser_id] = id }
  end

  def generate_questions
    count = (params[:question_count] || 10).to_i.clamp(5, 30)
    types = parse_types(params[:quiz_type])

    QuizGenerators::QuizGenerator.random(count: count, types: types)
  rescue StandardError => e
    Rails.logger.error("Quiz generation failed: #{e.message}")
    []
  end

  def parse_types(quiz_type)
    case quiz_type
    when "random", "", nil
      QuizGenerators::QuizGenerator::FAST_TYPES
    when "all"
      QuizGenerators::QuizGenerator::QUIZ_TYPES.keys
    else
      [ quiz_type.to_sym ]
    end
  end

  def quiz_type_options
    [
      { key: "random", name: "Random Mix", description: "A variety of football trivia questions", icon: "🎲", recommended: true },
      { key: "club_alumni", name: "Club Alumni", description: "Which club did all these players play for?", icon: "🏟️" },
      { key: "career_path", name: "Career Path", description: "Match players to their career journey", icon: "🛤️" },
      { key: "competition_connection", name: "Competition Connection", description: "Link players through competitions", icon: "🏆" },
      { key: "country_hopper", name: "Country Hopper", description: "Find players who played in multiple countries", icon: "🌍" },
      { key: "multi_club_crossover", name: "Multi-Club Crossover", description: "Find clubs that multiple players share", icon: "🔀" }
    ]
  end

  # Serialize questions for database storage
  # Store full data since we have no size limits in the database
  def serialize_questions(questions)
    questions.map do |q|
      {
        "type" => q[:type].to_s,
        "prompt" => q[:prompt],
        "correct_answer" => Array(q[:correct_answer]),
        "answer_hint" => q[:answer_hint],
        "options" => serialize_options(q[:options]),
        "players" => serialize_players(q[:players])
      }
    end
  end

  def serialize_options(options)
    return [] unless options
    options.map do |opt|
      if opt.respond_to?(:id)
        { "id" => opt.id, "name" => opt.name }
      else
        { "id" => opt[:id] || opt["id"], "name" => opt[:name] || opt["name"] }
      end
    end
  end

  def serialize_players(players)
    return [] unless players
    players.map do |player|
      if player.respond_to?(:id)
        { "id" => player.id, "name" => player.name }
      else
        { "id" => player[:id] || player["id"], "name" => player[:name] || player["name"] }
      end
    end
  end
end

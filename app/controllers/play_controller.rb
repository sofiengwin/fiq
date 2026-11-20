# frozen_string_literal: true

class PlayController < ApplicationController
  allow_unauthenticated_access
  before_action :set_play_session, only: %i[question answer results destroy]

  # GET /play - Select quiz type
  def index
    @quiz_types = quiz_type_options
  end

  # POST /play - Start generated quiz
  # Q12: anonymous /play builds rule-based questions for this session only.
  # The saved-quiz creation record is never consulted here, and phase-2
  # shells play no part in tile rendering or scoring.
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
    @effective_limit = play_effective_limit(@question)
  end

  # POST /play/answer - Submit answer
  def answer
    redirect_to play_path and return unless @play_session&.game_active?

    # Q5 idempotency: a double-tap / double-submit replays the same
    # question_index the page was rendered with. The first submit advances
    # current_index, so a stale index means "already answered" — ignore it
    # instead of scoring the next question with a duplicated payload.
    # Absent param (older clients) still processes; correctness is always
    # re-validated server-side by QuizScoring exact match (the client's
    # correct_count hint is never trusted for scoring).
    if params[:question_index].present? &&
       params[:question_index].to_i != @play_session.current_index
      redirect_to play_question_path and return
    end

    @question = @play_session.current_question
    limit_ms = play_effective_limit_ms(@question)
    @time_taken_ms = params[:time_taken_ms].to_i
    # Q7: on zero the timer auto-submits an empty selection with full-limit
    # elapsed ms. Score it as a timeout (zero) through the same Q6 snap
    # path as a lock — never as a late correct answer.
    if play_timed_out?(@time_taken_ms, limit_ms)
      @selected = []
      @time_taken_ms = limit_ms
      @play_session.process_timeout!(effective_limit_ms: limit_ms)
    else
      @selected = Array(params[:selected_ids]).map(&:to_i).reject(&:zero?)
      @play_session.process_answer!(
        params[:selected_ids],
        time_taken_ms: @time_taken_ms,
        effective_limit_ms: limit_ms
      )
    end
    @last_response = @play_session.responses.last || {}
    @points = @last_response["points"].to_i
    @tiles = play_snap_tiles(@question, @selected)
    @snap_next_url = @play_session.game_complete? ? play_results_path : play_question_path

    respond_to do |format|
      # Q6: Turbo (form_with) submissions get the snap reveal + auto-advance.
      format.turbo_stream
      # Non-JS fallback keeps the Q5 redirect behavior.
      format.html do
        if @play_session.game_complete?
          redirect_to play_results_path
        else
          redirect_to play_question_path
        end
      end
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

  # Countdown slot value for the shared play screen (Q3). Serialized play
  # questions rarely carry their own limit, so this falls back to the locked
  # 20s default. Q7 owns ticking/timeout behavior; this is display only.
  def play_effective_limit(question)
    seconds = question["time_limit_seconds"] ||
              question["effective_limit_seconds"] ||
              QuizScoring::DEFAULT_LIMIT_SECONDS
    seconds.to_i
  end

  def play_effective_limit_ms(question)
    play_effective_limit(question).to_i * 1000
  end

  # Q7 timeout check: elapsed ms at/over the limit means the countdown hit
  # zero, so the submit goes through process_timeout! (zero) rather than
  # process_answer!. An explicit timeout flag covers clients that send one.
  def play_timed_out?(time_taken_ms, limit_ms)
    params[:timeout].to_s == "1" || params[:timeout].to_s == "true" ||
      time_taken_ms.to_i >= limit_ms.to_i
  end

  # Q6 snap tiles for a serialized /play question: the exact correct set
  # from stored data and the picked set from this submit. Colors are left
  # to the snap partial (position-based cycle, same as the play screen the
  # user just tapped). Shown +N comes from the persisted PlaySession
  # response (QuizScoring), never recomputed here.
  def play_snap_tiles(question, selected_ids)
    correct_ids = Array(question["correct_answer"]).map(&:to_i)
    picked_ids = Array(selected_ids).map(&:to_i)
    Array(question["options"]).map do |opt|
      opt = opt.is_a?(Hash) ? opt : {}
      id = (opt["id"] || opt[:id]).to_i
      { id: id,
        text: opt["name"] || opt[:name],
        image_url: opt["image_url"] || opt[:image_url],
        correct: correct_ids.include?(id),
        picked: picked_ids.include?(id) }
    end
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
      options = q[:options] || q["options"] || q[:club_options] || q["club_options"]
      correct = q[:correct_answer] || q["correct_answer"] || q[:correct_clubs] || q["correct_clubs"]
      {
        "type" => q[:type].to_s,
        "prompt" => q[:prompt],
        "correct_answer" => Array(correct),
        "answer_hint" => q[:answer_hint],
        "options" => serialize_options(options),
        "players" => serialize_players(q[:players]),
        "points" => q[:points] || q["points"] || QuizScoring::DEFAULT_BASE_POINTS
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

# frozen_string_literal: true

require "test_helper"

# Locks the Q2 scoring contract: exact-match-or-zero + speed + streak,
# shared by ScoreCalculator/QuizAttempt and PlaySession, with scoring_mode
# ignored in play and timeout scoring zero through the same scorer.
class QuizScoringTest < ActiveSupport::TestCase
  setup do
    @quiz = Quiz.create!(title: "Scoring lock", time_limit_seconds: 20,
                         scoring_mode: "partial_credit")
    @question = @quiz.questions.create!(text: "Pick the two correct",
                                        points: 1000, time_limit_seconds: 20,
                                        order_index: 0)
    @follow_up = @quiz.questions.create!(text: "Follow-up", points: 1000,
                                         time_limit_seconds: 20, order_index: 1)
    @opt_a = @question.answer_options.create!(text: "A", is_correct: true, order_index: 0)
    @opt_b = @question.answer_options.create!(text: "B", is_correct: true, order_index: 1)
    @opt_c = @question.answer_options.create!(text: "C", is_correct: false, order_index: 2)
    @opt_d = @question.answer_options.create!(text: "D", is_correct: false, order_index: 3)
    @opt_e = @follow_up.answer_options.create!(text: "A", is_correct: true, order_index: 0)
    @opt_f = @follow_up.answer_options.create!(text: "B", is_correct: false, order_index: 1)
  end

  def calculate(question, selected_ids, time_taken_ms, streak = 0)
    ScoreCalculator.new(
      question: question,
      selected_answer_ids: selected_ids,
      time_taken_ms: time_taken_ms,
      current_streak: streak
    ).calculate
  end

  test "partial multi-select scores zero, exact match scores" do
    subset = calculate(@question, [ @opt_a.id ], 1_000)
    assert_equal 0, subset.final_score
    assert_not subset.correct?
    assert_equal 0, subset.new_streak

    superset = calculate(@question, [ @opt_a.id, @opt_b.id, @opt_c.id ], 1_000)
    assert_equal 0, superset.final_score
    assert_not superset.correct?

    exact = calculate(@question, [ @opt_a.id, @opt_b.id ], 1_000)
    assert exact.correct?
    assert_operator exact.final_score, :>, 0
    assert_equal 1, exact.new_streak
  end

  test "faster exact answer on the same question scores strictly higher" do
    correct_ids = [ @opt_a.id, @opt_b.id ]
    fast = calculate(@question, correct_ids, 1_000)
    slow = calculate(@question, correct_ids, 19_000)

    assert fast.correct?
    assert slow.correct?
    assert_operator fast.final_score, :>, slow.final_score
  end

  test "correct increments streak, wrong resets it to zero" do
    attempt = @quiz.quiz_attempts.create!

    attempt.submit_response(question_id: @question.id,
                            selected_answer_ids: [ @opt_a.id, @opt_b.id ],
                            time_taken_ms: 1_000)
    assert_equal 1, attempt.reload.streak

    response = attempt.submit_response(question_id: @follow_up.id,
                                       selected_answer_ids: [ @opt_f.id ],
                                       time_taken_ms: 1_000)
    assert_equal 0, response.score_awarded
    assert_equal 0, attempt.reload.streak
  end

  test "timeout scores zero through the same scorer" do
    timed_out = QuizScoring.timeout(
      correct_ids: [ @opt_a.id, @opt_b.id ],
      base_points: 1000,
      effective_limit_ms: 20_000,
      streak: 2
    )
    assert_equal 0, timed_out.points
    assert_equal 0, timed_out.new_streak
    assert_not timed_out.correct?

    empty = calculate(@question, [], 20_000, 2)
    assert_equal 0, empty.final_score
    assert_equal 0, empty.new_streak

    attempt = @quiz.quiz_attempts.create!
    response = attempt.submit_timeout(@question.id)
    assert_equal 0, response.score_awarded
    assert_equal 0, attempt.reload.streak
  end

  test "scoring_mode value does not change the play score" do
    correct_ids = [ @opt_a.id, @opt_b.id ]

    @quiz.update!(scoring_mode: "partial_credit")
    partial_credit_score = calculate(@question, correct_ids, 5_000, 1)

    @quiz.update!(scoring_mode: "all_or_nothing")
    all_or_nothing_score = calculate(@question.reload, correct_ids, 5_000, 1)

    assert_equal partial_credit_score.final_score, all_or_nothing_score.final_score
    assert_equal partial_credit_score.new_streak, all_or_nothing_score.new_streak
  end

  test "play session uses the same formula as the saved-quiz path" do
    correct_ids = [ @opt_a.id, @opt_b.id ]
    session = PlaySession.create!(
      session_id: "q2-lock",
      questions: [
        { "prompt" => "Pick the two correct", "correct_answer" => correct_ids,
          "points" => 1000, "options" => [] }
      ]
    )

    session.process_answer!(correct_ids,
                            time_taken_ms: 1_000, effective_limit_ms: 20_000)

    expected = QuizScoring.score(
      correct_ids: correct_ids, selected_ids: correct_ids,
      base_points: 1000, time_taken_ms: 1_000,
      effective_limit_ms: 20_000, streak: 0
    )
    assert_equal expected.points, session.total_score
    assert_equal expected.new_streak, session.streak
    assert session.responses.last["is_correct"]
  end

  test "play session timeout scores zero and resets the streak" do
    session = PlaySession.create!(
      session_id: "q2-timeout",
      streak: 2,
      questions: [
        { "prompt" => "Pick the two correct",
          "correct_answer" => [ @opt_a.id, @opt_b.id ], "options" => [] }
      ]
    )

    session.process_timeout!

    assert_equal 0, session.total_score
    assert_equal 0, session.streak
    assert_equal 1, session.current_index
    assert_not session.responses.last["is_correct"]
  end

  test "tie-break is wall-clock duration, faster wins" do
    started = Time.zone.parse("2026-01-01 12:00:00")
    assert_equal 30, QuizScoring.duration_seconds(started, started + 30.seconds)
    assert_nil QuizScoring.duration_seconds(started, nil)
    assert QuizScoring.faster?(started, started + 10.seconds,
                               started, started + 60.seconds)
    assert_not QuizScoring.faster?(started, started + 60.seconds,
                                   started, started + 10.seconds)

    slow = @quiz.quiz_attempts.create!(total_score: 500, streak: 1,
                                       started_at: started,
                                       completed_at: started + 60.seconds)
    fast = @quiz.quiz_attempts.create!(total_score: 500, streak: 1,
                                       started_at: started,
                                       completed_at: started + 10.seconds)
    best = @quiz.quiz_attempts.create!(total_score: 900, streak: 3,
                                       started_at: started,
                                       completed_at: started + 100.seconds)
    unfinished = @quiz.quiz_attempts.create!(total_score: 999, streak: 9,
                                             started_at: started,
                                             completed_at: nil)

    assert_equal [ best.id, fast.id, slow.id ], @quiz.quiz_attempts.ranked.pluck(:id)
    assert_not_includes @quiz.quiz_attempts.ranked.pluck(:id), unfinished.id
    assert_equal 10, fast.duration_seconds
  end
end

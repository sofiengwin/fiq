# Kahoot-Style Web Application — Technical Specification & Implementation Plan

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Technology Stack](#2-technology-stack)
3. [Data Models](#3-data-models)
4. [Rails API Design](#4-rails-api-design)
5. [Scoring Logic](#5-scoring-logic)
6. [User Flows](#6-user-flows)

---

## 1. Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────┐
│                        CLIENT                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │          Quiz App (Rails + Hotwire)               │  │
│  │                                                   │  │
│  │  • Create & edit quizzes                          │  │
│  │  • Browse & search quizzes                        │  │
│  │  • Take quizzes (self-paced)                      │  │
│  │  • View results                                   │  │
│  │                                                   │  │
│  │  Turbo + Stimulus (HTML over the wire)            │  │
│  └─────────────────────┬─────────────────────────────┘  │
└─────────────────────────┼────────────────────────────────┘
                          │ HTTP (Turbo Frames/Streams)
                          │
┌─────────────────────────┴────────────────────────────────┐
│                  RAILS APPLICATION                        │
│  ┌────────────────────────────────────────────────────┐  │
│  │           Ruby on Rails 8.x (Full Stack)           │  │
│  │                                                    │  │
│  │  ┌────────────────────────────────────────────┐    │  │
│  │  │  Controllers (RESTful Actions)             │    │  │
│  │  └────────────────────────────────────────────┘    │  │
│  │                                                    │  │
│  │  ┌────────────────────────────────────────────┐    │  │
│  │  │  Views (ERB + Turbo Frames/Streams)        │    │  │
│  │  └────────────────────────────────────────────┘    │  │
│  │                                                    │  │
│  │  ┌────────────────────────────────────────────┐    │  │
│  │  │  Models (ActiveRecord + Business Logic)    │    │  │
│  │  └────────────────────────────────────────────┘    │  │
│  └────────────────────────┬───────────────────────────┘  │
└────────────────────────────┼──────────────────────────────┘
                             │
┌────────────────────────────┴──────────────────────────────┐
│                      DATA LAYER                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │   PostgreSQL                                        │  │
│  │   - Quizzes, Questions, AnswerOptions               │  │
│  │   - QuizAttempts, Responses, ResponseAnswers        │  │
│  └─────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

- **Fullstack Ruby on Rails**: Single monolithic application handling both frontend and backend.
  No separate API layer — Rails controllers serve HTML with Turbo enhancements.
- **Hotwire (Turbo + Stimulus)**: Modern Rails frontend approach. Turbo Frames for partial
  page updates, Turbo Streams for real-time updates, Stimulus for JavaScript behaviors.
- **RESTful routes**: Standard Rails resource routing for all CRUD operations. Clean URLs
  and conventional controller actions.
- **Server-rendered views**: ERB templates with Tailwind CSS for styling. No JavaScript
  framework — just vanilla Stimulus controllers for interactivity.
- **No authentication**: Anyone can create and take quizzes without logging in. Quiz attempts
  are anonymous and tracked only by attempt ID stored in session/cookie.
- **Self-paced experience**: Timers run client-side via Stimulus controllers. No real-time
  synchronization between users — each person takes the quiz independently.
- **Kahoot-inspired UI/UX**: The quiz player interface should closely follow Kahoot's iconic
  design language:
  - Bold, vibrant colored answer buttons (red, blue, green, yellow, orange, purple)
  - Large, easy-to-tap answer areas with geometric shapes
  - Prominent countdown timer with visual urgency as time runs low
  - Celebratory animations and sound effects for correct answers
  - Score popup after each question showing points earned and streak bonuses
  - Leaderboard-style results screen with fun rankings and statistics
  - Dark/purple background theme with high-contrast, playful typography
  - Mobile-first responsive design optimized for touch interactions

---

## 2. Technology Stack

| Layer                    | Technology                              | Rationale                                                                                         |
| ------------------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Framework**            | Ruby on Rails 8.x                       | Full-stack framework with built-in conventions for models, views, controllers, and database.      |
| **Frontend**             | Hotwire (Turbo + Stimulus)              | Modern Rails approach for dynamic UIs without heavy JavaScript frameworks.                        |
| **Styling**              | Tailwind CSS                            | Rapid UI development, utility-first CSS, consistent design system.                               |
| **JavaScript**           | Stimulus + Importmaps                   | Lightweight JS controllers for interactivity; no build step required with importmaps.             |
| **ORM**                  | ActiveRecord                            | Rails default ORM with migrations, validations, associations, and query interface.                |
| **Database**             | PostgreSQL                              | Reliable relational database with excellent Rails support.                                        |
| **Background Jobs**      | Solid Queue                             | Rails 8 default for background job processing; database-backed, no Redis required.                |
| **Caching**              | Solid Cache                             | Rails 8 default for caching; database-backed.                                                     |
| **Real-time Updates**    | Turbo Streams (via Action Cable)        | Push updates to connected clients for live score updates if needed.                               |
| **Testing**              | Minitest + Capybara                     | Rails default testing framework with system tests for full-stack testing.                         |
| **Validation**           | ActiveModel Validations                 | Built-in model validations with custom validators for complex rules.                              |
| **Deployment**           | Kamal 2                                 | Rails 8 default deployment tool; Docker-based, zero-downtime deploys.                             |

---

## 3. Data Models

### Entity Relationship Diagram

```
┌──────────────────┐       ┌──────────────────┐
│      QUIZ        │       │    QUESTION      │
├──────────────────┤       ├──────────────────┤
│ id (PK)          │──┐    │ id (PK)          │
│ title            │  │    │ quiz_id (FK)     │
│ description      │  └───>│ order_index      │
│ time_limit_secs  │       │ text             │
│ scoring_mode     │       │ image_url        │
│ created_at       │       │ time_limit_secs  │
│ updated_at       │       │ points           │
└──────────────────┘       │ created_at       │
         │                 └────────┬─────────┘
         │                          │
         │                 ┌────────┘
         │                 │
┌────────┴─────────┐    ┌──┴───────────────┐
│  QUIZ_ATTEMPT    │    │  ANSWER_OPTION   │
├──────────────────┤    ├──────────────────┤
│ id (PK)          │    │ id (PK)          │
│ quiz_id (FK)     │    │ question_id (FK) │
│ total_score      │    │ order_index      │
│ streak           │    │ text             │
│ started_at       │    │ is_correct       │
│ completed_at     │    │ color            │
└───────┬──────────┘    └──────────────────┘
        │                        │
        │                        │
        │  ┌──────────────────┐  │
        └─>│    RESPONSE      │  │
           ├──────────────────┤  │
           │ id (PK)          │  │
           │ attempt_id (FK)  │  │
           │ question_id (FK) │  │
           │ time_taken_ms    │  │
           │ score_awarded    │  │
           │ submitted_at     │  │
           └───────┬──────────┘  │
                   │             │
           ┌───────┘    ┌───────┘
           │            │
    ┌──────┴────────────┴──┐
    │   RESPONSE_ANSWER    │
    │   (join table)       │
    ├──────────────────────┤
    │ response_id (FK)     │
    │ answer_option_id(FK) │
    └──────────────────────┘
```

### Entity Descriptions

#### Quiz
- Contains metadata and configuration for a set of questions.
- `time_limit_seconds`: Default per-question time limit (can be overridden per question).
- `scoring_mode`: `"partial_credit"` or `"all_or_nothing"` — set at creation time.

#### Question
- Belongs to a `Quiz`. Ordered by `order_index`.
- `image_url`: Optional image attachment for the question.
- `time_limit_seconds`: Per-question override (falls back to quiz default if `null`).
- `points`: Base points for this question (default `1000`).

#### AnswerOption
- Belongs to a `Question`. Each question has 2–6 answer options.
- `is_correct`: Boolean — one or more options can be correct (multi-correct support).
- `color`: One of `"red"`, `"blue"`, `"green"`, `"yellow"`, `"orange"`, `"purple"` — for the Kahoot-style colored buttons.

#### QuizAttempt
- One self-paced play-through of a `Quiz`.
- `total_score`: Running total, updated after each response submission.
- `streak`: Current consecutive-correct streak.
- `completed_at`: Set when the last question is answered (nullable while in progress).

#### Response
- One submission for one question within an attempt.
- `time_taken_ms`: Milliseconds from question display to submission.
- `score_awarded`: Calculated score for this response.

#### ResponseAnswer (Join Table)
- Links a `Response` to the `AnswerOption`(s) the user selected.
- Supports multiple selections per question.

### Key Design Decisions

- **Response vs ResponseAnswer separation**: A `Response` is one submission for one question.
  The `ResponseAnswer` join table captures which answer options were selected, supporting
  multiple selections per question.
- **QuizAttempt tracks state**: The `total_score` and `streak` fields on `QuizAttempt` are
  updated after each response, allowing the client to display running totals.
- **Scoring mode on Quiz**: Stored at the quiz level so the creator decides at creation time.
- **No user identity**: Attempts are anonymous. Anyone can create quizzes or take them without
  logging in.

---

## 4. Rails API Design

### 4.1 Routes Configuration

Rails uses RESTful routing conventions. Below is the complete routes configuration.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "home#index"

  resources :quizzes do
    member do
      post :duplicate
    end
    resources :questions, except: [:index, :show] do
      resources :answer_options, except: [:index, :show]
    end
  end

  resources :quiz_attempts, only: [:show, :create] do
    member do
      get :results
    end
    resources :responses, only: [:create]
  end
end
```

### 4.2 Controllers

#### QuizzesController

```ruby
# app/controllers/quizzes_controller.rb
class QuizzesController < ApplicationController
  def index
    @quizzes = Quiz.search(params[:search])
                   .order(created_at: :desc)
                   .page(params[:page])
  end

  def show
    @quiz = Quiz.find(params[:id])
  end

  def new
    @quiz = Quiz.new
    @quiz.questions.build.answer_options.build
  end

  def create
    @quiz = Quiz.new(quiz_params)
    if @quiz.save
      redirect_to @quiz, notice: "Quiz created successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @quiz = Quiz.find(params[:id])
  end

  def update
    @quiz = Quiz.find(params[:id])
    if @quiz.update(quiz_params)
      redirect_to @quiz, notice: "Quiz updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quiz = Quiz.find(params[:id])
    @quiz.destroy
    redirect_to quizzes_path, notice: "Quiz deleted."
  end

  def duplicate
    @original = Quiz.find(params[:id])
    @quiz = @original.duplicate
    redirect_to edit_quiz_path(@quiz), notice: "Quiz duplicated!"
  end

  private

  def quiz_params
    params.require(:quiz).permit(
      :title, :description, :time_limit_seconds, :scoring_mode,
      questions_attributes: [
        :id, :text, :image_url, :time_limit_seconds, :points, :order_index, :_destroy,
        answer_options_attributes: [:id, :text, :is_correct, :order_index, :color, :_destroy]
      ]
    )
  end
end
```

#### QuizAttemptsController

```ruby
# app/controllers/quiz_attempts_controller.rb
class QuizAttemptsController < ApplicationController
  def show
    @attempt = QuizAttempt.find(params[:id])
    @current_question = @attempt.current_question
  end

  def create
    @quiz = Quiz.find(params[:quiz_id])
    @attempt = @quiz.quiz_attempts.create!(started_at: Time.current)
    redirect_to quiz_attempt_path(@attempt)
  end

  def results
    @attempt = QuizAttempt.includes(responses: [:question, :selected_answers])
                          .find(params[:id])
    @results = @attempt.calculate_results
  end
end
```

#### ResponsesController

```ruby
# app/controllers/responses_controller.rb
class ResponsesController < ApplicationController
  def create
    @attempt = QuizAttempt.find(params[:quiz_attempt_id])
    @response = @attempt.submit_response(response_params)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to quiz_attempt_path(@attempt) }
    end
  end

  private

  def response_params
    params.require(:response).permit(:question_id, :time_taken_ms, selected_answer_ids: [])
  end
end
```

### 4.3 View Examples

#### Quiz Player with Turbo Frames

```erb
<%# app/views/quiz_attempts/show.html.erb %>
<div class="quiz-player" data-controller="quiz-timer">
  <turbo-frame id="question-frame">
    <%= render "question", question: @current_question, attempt: @attempt %>
  </turbo-frame>
</div>
```

```erb
<%# app/views/quiz_attempts/_question.html.erb %>
<div class="question-card">
  <div class="timer" data-quiz-timer-target="display">
    <%= question.effective_time_limit %>
  </div>

  <h2><%= question.text %></h2>
  <% if question.image_url.present? %>
    <%= image_tag question.image_url, class: "question-image" %>
  <% end %>

  <%= form_with url: quiz_attempt_responses_path(attempt),
                data: { turbo_frame: "question-frame" } do |f| %>
    <%= f.hidden_field :question_id, value: question.id %>
    <%= f.hidden_field :time_taken_ms, data: { quiz_timer_target: "timeTaken" } %>

    <div class="answer-grid" data-controller="answer-selection">
      <% question.answer_options.each do |answer| %>
        <label class="answer-button answer-<%= answer.color %>"
               data-answer-selection-target="option">
          <%= f.check_box :selected_answer_ids,
                          { multiple: true },
                          answer.id, nil %>
          <span><%= answer.text %></span>
        </label>
      <% end %>
    </div>

    <%= f.submit "Submit", class: "submit-button" %>
  <% end %>
</div>
```

### 4.4 Stimulus Controllers

```javascript
// app/javascript/controllers/quiz_timer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "timeTaken"]
  static values = { seconds: Number }

  connect() {
    this.startTime = Date.now()
    this.remaining = this.secondsValue
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.interval)
  }

  tick() {
    this.remaining -= 1
    this.displayTarget.textContent = this.remaining

    if (this.remaining <= 0) {
      clearInterval(this.interval)
      this.autoSubmit()
    }
  }

  submit() {
    this.timeTakenTarget.value = Date.now() - this.startTime
  }

  autoSubmit() {
    this.submit()
    this.element.querySelector("form").requestSubmit()
  }
}
```

```javascript
// app/javascript/controllers/answer_selection_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option"]

  toggle(event) {
    const option = event.currentTarget
    option.classList.toggle("selected")
  }
}
```

### 4.5 Turbo Stream Response

```erb
<%# app/views/responses/create.turbo_stream.erb %>
<turbo-stream action="replace" target="question-frame">
  <template>
    <% if @attempt.completed? %>
      <div class="completion-card">
        <h2>Quiz Complete!</h2>
        <p>Your score: <%= @attempt.total_score %></p>
        <%= link_to "See Results", results_quiz_attempt_path(@attempt),
                    class: "btn btn-primary" %>
      </div>
    <% else %>
      <%= render "quiz_attempts/question_result",
                 response: @response,
                 next_question: @attempt.current_question %>
    <% end %>
  </template>
</turbo-stream>

<turbo-stream action="update" target="score-display">
  <template>
    <span>Score: <%= @attempt.total_score %></span>
  </template>
</turbo-stream>
```

---

## 5. Scoring Logic

### 5.1 Two Scoring Modes

The quiz creator chooses one at quiz creation time via the `scoringMode` field.

#### Mode A: Partial Credit (Default)

For a question with `N` correct answers and `M` total answer options:

```
correctSelections   = count of selected answers that ARE correct
incorrectSelections = count of selected answers that are NOT correct

if incorrectSelections > 0:
    rawScore = max(0, (correctSelections - incorrectSelections) / N)
else:
    rawScore = correctSelections / N

basePoints = question.points   // default 1000
timeBonus  = 1 - (time_taken_ms / (time_limit_seconds * 1000)) × 0.5

score = round(basePoints × rawScore × (0.5 + timeBonus))
```

**Explanation:**
- Selecting all correct answers and no wrong ones yields full points.
- Each wrong selection penalizes by canceling out one correct selection.
- Time bonus scales from 100% (instant answer) to 50% (answered at deadline). Even slow
  correct answers get at least half credit.
- Floor is 0 — no negative scores.

**Example**: Question has 2 correct out of 4. User selects both correct + 1 wrong in 8s
(limit 20s):
- `correctSelections=2, incorrectSelections=1, N=2` → `rawScore = (2-1)/2 = 0.5`
- `timeBonus = 1 - (8000/20000) × 0.5 = 0.8`
- `score = round(1000 × 0.5 × (0.5 + 0.8)) = round(650) = 650`

#### Mode B: All-or-Nothing

```
if selectedAnswers == exactSetOfCorrectAnswers:
    rawScore = 1.0
else:
    rawScore = 0.0

score = round(question.points × rawScore × (0.5 + timeBonus))
```

You must select **exactly** the correct answers — no more, no fewer.

### 5.2 Streak Bonus

To add excitement, a streak multiplier applies to consecutive correctly-answered questions:

| Consecutive Correct | Multiplier |
| ------------------- | ---------- |
| 1                   | ×1.0       |
| 2                   | ×1.1       |
| 3                   | ×1.2       |
| 4+                  | ×1.3 (cap) |

A "correct" answer for streak purposes means `rawScore > 0` (i.e., you got at least partial
credit). The final score formula with streak:

```
finalScore = round(score × streakMultiplier)
```

### 5.3 No-Answer Handling

- If the user doesn't submit before the timer expires → `score = 0`, streak resets to 0.
- If the user submits an empty `selectedAnswerIds` array → `score = 0`, streak resets.

### 5.4 Score Calculation Service

The scoring logic is implemented in a Ruby service object used by the Response model:

```ruby
# app/services/score_calculator.rb
class ScoreCalculator
  STREAK_MULTIPLIERS = { 1 => 1.0, 2 => 1.1, 3 => 1.2 }.freeze
  MAX_STREAK_MULTIPLIER = 1.3

  def initialize(question:, selected_answer_ids:, time_taken_ms:, current_streak:)
    @question = question
    @selected_answer_ids = selected_answer_ids.map(&:to_i)
    @time_taken_ms = time_taken_ms
    @current_streak = current_streak
  end

  def calculate
    @correct_ids = @question.answer_options.where(is_correct: true).pluck(:id)
    @raw_score = calculate_raw_score
    @time_bonus = calculate_time_bonus
    @base_score = (@question.points * @raw_score * (0.5 + @time_bonus)).round
    @streak_multiplier = calculate_streak_multiplier
    @final_score = (@base_score * @streak_multiplier).round
    @new_streak = @raw_score > 0 ? @current_streak + 1 : 0

    Result.new(
      raw_score: @raw_score,
      time_bonus: @time_bonus,
      base_score: @base_score,
      streak_multiplier: @streak_multiplier,
      final_score: @final_score,
      new_streak: @new_streak,
      correct?: @raw_score > 0
    )
  end

  private

  def calculate_raw_score
    return 0 if @selected_answer_ids.empty?

    case @question.quiz.scoring_mode
    when "partial_credit"
      calculate_partial_credit
    when "all_or_nothing"
      @selected_answer_ids.sort == @correct_ids.sort ? 1.0 : 0.0
    end
  end

  def calculate_partial_credit
    correct_selections = (@selected_answer_ids & @correct_ids).size
    incorrect_selections = (@selected_answer_ids - @correct_ids).size

    if incorrect_selections > 0
      [(correct_selections - incorrect_selections).to_f / @correct_ids.size, 0].max
    else
      correct_selections.to_f / @correct_ids.size
    end
  end

  def calculate_time_bonus
    time_limit_ms = @question.effective_time_limit * 1000
    1.0 - (@time_taken_ms.to_f / time_limit_ms) * 0.5
  end

  def calculate_streak_multiplier
    STREAK_MULTIPLIERS[@new_streak] || MAX_STREAK_MULTIPLIER
  end

  Result = Struct.new(:raw_score, :time_bonus, :base_score, :streak_multiplier,
                      :final_score, :new_streak, :correct?, keyword_init: true)
end
```

---

## 6. User Flows

### 6.1 Quiz Creation Flow

```
[Land on homepage]
       │
       ▼
[Click "Create Quiz"]
       │
       ▼
[Enter quiz title, description, scoring mode, default time limit]
       │
       ▼
[Add Question 1:
 - Enter question text
 - Add 2–6 answer options
 - Mark 1+ as correct
 - Set optional per-question time limit]
       │
       ▼
[Add another question?] ──Yes──> [Add Question N] ──┐
       │                                              │
       No                                             │
       │ <────────────────────────────────────────────┘
       ▼
[Review & Save Quiz]  ← calls `createQuiz` mutation
       │
       ▼
[Quiz saved — redirect to quiz detail page with shareable link]
```

### 6.2 Quiz Taking Flow

```
[Land on homepage or browse quizzes]
       │
       ▼
[Browse quiz list or open a direct quiz link]
  ← calls `quizzes` query
       │
       ▼
[Select a quiz → Quiz detail page]
  ← calls `quiz(id)` query
       │
       ▼
[See quiz title, description, question count, scoring mode]
       │
       ▼
[Click "Start Quiz"]
  ← calls `startQuizAttempt` mutation
       │
       ▼
[Question 1 appears with answer options as colored buttons]
[Client-side timer counting down]
       │
       ▼
[Tap one or more answers (multi-select enabled)]
[Selected answers are highlighted]
       │
       ▼
[Tap "Submit" to submit (or auto-submit when timer expires)]
  ← calls `submitResponse` mutation
       │
       ▼
[See correct answers highlighted + your score for this question]
       │
       ▼
[Click "Next Question"]
       │
       ▼
[More questions?] ──Yes──> [Next question displayed] ──┐
       │                                                 │
       No                                                │
       │ <──────────────────────────────────────────────┘
       ▼
[Results screen: total score, per-question breakdown, streak info]
  ← calls `attemptResults` query
       │
       ▼
[Option: Retake quiz or browse more quizzes]
```

### 6.3 Key UI Screens

| #  | Screen           | Route                          | Key Components                                                  |
| -- | ---------------- | ------------------------------ | --------------------------------------------------------------- |
| 1  | Landing Page     | `/`                            | Hero section, "Create Quiz" CTA, "Browse Quizzes" button        |
| 2  | Quiz Browser     | `/quizzes`                     | Quiz list cards with search, filter by topic (Turbo Frame)      |
| 3  | Quiz Detail      | `/quizzes/:id`                 | Quiz info, question count, scoring mode, "Start Quiz" button    |
| 4  | Quiz Editor      | `/quizzes/new`, `/quizzes/:id/edit` | Nested form with Stimulus, drag-reorder, live preview       |
| 5  | Quiz Player      | `/quiz_attempts/:id`           | Question text, answer buttons (multi-select), timer, submit     |
| 6  | Question Result  | `/quiz_attempts/:id` (Turbo)   | Correct/wrong feedback, score for this question, next button    |
| 7  | Final Results    | `/quiz_attempts/:id/results`   | Total score, per-question breakdown, streak summary, retake CTA |

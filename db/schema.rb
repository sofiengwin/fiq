# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_29_214226) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_admin_comments", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "namespace"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "answer_options", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "is_correct"
    t.integer "order_index"
    t.bigint "question_id", null: false
    t.string "text"
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_answer_options_on_question_id"
  end

  create_table "careers", force: :cascade do |t|
    t.integer "appearances", default: 0
    t.datetime "created_at", null: false
    t.daterange "duration"
    t.bigint "football_team_id", null: false
    t.bigint "player_id", null: false
    t.datetime "updated_at", null: false
    t.index ["duration"], name: "index_careers_on_duration", using: :gist
    t.index ["football_team_id"], name: "index_careers_on_football_team_id"
    t.index ["player_id"], name: "index_careers_on_player_id"
  end

  create_table "competitions", force: :cascade do |t|
    t.bigint "country_id"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_competitions_on_country_id"
    t.index ["external_id"], name: "index_competitions_on_external_id", unique: true
  end

  create_table "competitions_football_teams", id: false, force: :cascade do |t|
    t.bigint "competition_id", null: false
    t.bigint "football_team_id", null: false
    t.index ["competition_id", "football_team_id"], name: "idx_comp_team"
    t.index ["football_team_id", "competition_id"], name: "idx_team_comp"
  end

  create_table "countries", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_countries_on_name", unique: true
  end

  create_table "football_teams", force: :cascade do |t|
    t.string "code"
    t.bigint "country_id"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_football_teams_on_country_id"
    t.index ["external_id"], name: "index_football_teams_on_external_id", unique: true
  end

  create_table "players", force: :cascade do |t|
    t.integer "age"
    t.integer "appearances", default: 0
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "first_name"
    t.string "last_name"
    t.string "name", null: false
    t.string "position"
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_players_on_external_id", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "image_url"
    t.integer "order_index"
    t.integer "points"
    t.bigint "quiz_id", null: false
    t.text "text"
    t.integer "time_limit_seconds"
    t.datetime "updated_at", null: false
    t.index ["quiz_id"], name: "index_questions_on_quiz_id"
  end

  create_table "quiz_attempts", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "quiz_id", null: false
    t.datetime "started_at"
    t.integer "streak"
    t.integer "total_score"
    t.datetime "updated_at", null: false
    t.index ["quiz_id"], name: "index_quiz_attempts_on_quiz_id"
  end

  create_table "quizzes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "scoring_mode"
    t.integer "time_limit_seconds"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "response_answers", force: :cascade do |t|
    t.bigint "answer_option_id", null: false
    t.datetime "created_at", null: false
    t.bigint "response_id", null: false
    t.datetime "updated_at", null: false
    t.index ["answer_option_id"], name: "index_response_answers_on_answer_option_id"
    t.index ["response_id"], name: "index_response_answers_on_response_id"
  end

  create_table "responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "question_id", null: false
    t.bigint "quiz_attempt_id", null: false
    t.integer "score_awarded"
    t.datetime "submitted_at"
    t.integer "time_taken_ms"
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_responses_on_question_id"
    t.index ["quiz_attempt_id"], name: "index_responses_on_quiz_attempt_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "admin_since"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "answer_options", "questions"
  add_foreign_key "careers", "football_teams"
  add_foreign_key "careers", "players"
  add_foreign_key "competitions", "countries"
  add_foreign_key "football_teams", "countries"
  add_foreign_key "questions", "quizzes"
  add_foreign_key "quiz_attempts", "quizzes"
  add_foreign_key "response_answers", "answer_options"
  add_foreign_key "response_answers", "responses"
  add_foreign_key "responses", "questions"
  add_foreign_key "responses", "quiz_attempts"
  add_foreign_key "sessions", "users"
end

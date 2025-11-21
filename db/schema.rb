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

ActiveRecord::Schema[8.1].define(version: 2025_11_21_060152) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "careers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "player_id", null: false
    t.date "start_date"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_careers_on_player_id"
    t.index ["team_id"], name: "index_careers_on_team_id"
  end

  create_table "countries", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "leagues", force: :cascade do |t|
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_leagues_on_country_id"
  end

  create_table "players", force: :cascade do |t|
    t.integer "age"
    t.integer "appearances"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "first_name"
    t.string "last_name"
    t.string "name"
    t.string "position"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_players_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "code"
    t.bigint "country_id"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_teams_on_country_id"
  end

  add_foreign_key "careers", "players"
  add_foreign_key "careers", "teams"
  add_foreign_key "leagues", "countries"
  add_foreign_key "players", "teams"
  add_foreign_key "teams", "countries"
end

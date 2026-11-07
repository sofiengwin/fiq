require "test_helper"

# T1 — Migrations: stats prereq + last_refreshed_at.
# Derived from tickets.md T1 "Done when" (not from implementation):
#   - players += dob/nationality/photo_url + last_refreshed_at
#   - football_teams += last_refreshed_at
#   - careers += goals (default 0, nullable day-one) / assists / cards_yellow /
#     cards_red (nullable) + competition_id (nullable FK -> competitions) +
#     last_refreshed_at
#   - index on each last_refreshed_at and on careers.competition_id
#   - no minutes_played anywhere in db/ or app/models
class StatsPrereqMigrationTest < ActiveSupport::TestCase
  def columns(table)
    ActiveRecord::Base.connection.columns(table).index_by(&:name)
  end

  def index_names(table)
    ActiveRecord::Base.connection.indexes(table).map(&:name)
  end

  def t1_country
    Country.find_or_create_by!(name: "T1 Testland")
  end

  def foreign_keys(table)
    ActiveRecord::Base.connection.foreign_keys(table)
  end

  def t1_team(name)
    FootballTeam.create!(name: name, country: t1_country)
  end

  # ---- players (T1: dob/nationality/photo_url + last_refreshed_at) ----

  test "players has dob as date" do
    col = columns("players")["dob"]
    assert_not_nil col, "players.dob is missing"
    assert_equal :date, col.type
  end

  test "players has nationality and photo_url as strings" do
    assert_equal :string, columns("players")["nationality"]&.type, "players.nationality missing or wrong type"
    assert_equal :string, columns("players")["photo_url"]&.type, "players.photo_url missing or wrong type"
  end

  test "players has last_refreshed_at datetime with index" do
    assert_equal :datetime, columns("players")["last_refreshed_at"]&.type
    assert_includes index_names("players"), "index_players_on_last_refreshed_at"
  end

  # ---- football_teams (T1: last_refreshed_at only) ----

  test "football_teams has last_refreshed_at datetime with index" do
    assert_equal :datetime, columns("football_teams")["last_refreshed_at"]&.type
    assert_includes index_names("football_teams"), "index_football_teams_on_last_refreshed_at"
  end

  # ---- careers (T1: goals/assists/cards + competition_id FK + last_refreshed_at) ----

  test "careers goals defaults to 0 but stays nullable for existing rows" do
    col = columns("careers")["goals"]
    assert_not_nil col, "careers.goals is missing"
    assert_equal :integer, col.type
    assert_equal 0, col.default, "careers.goals must default to 0"
    assert col.null, "careers.goals must stay nullable on day one (T1: enforced at model layer in T6)"
  end

  test "careers assists and cards are nullable integers with no default" do
    %w[assists cards_yellow cards_red].each do |name|
      col = columns("careers")[name]
      assert_not_nil col, "careers.#{name} is missing"
      assert_equal :integer, col.type, "careers.#{name} must be integer"
      assert col.null, "careers.#{name} must be nullable"
      assert_nil col.default, "careers.#{name} must have no default"
    end
  end

  test "careers competition_id is nullable with fk to competitions and index" do
    col = columns("careers")["competition_id"]
    assert_not_nil col, "careers.competition_id is missing"
    assert col.null, "careers.competition_id must be nullable"

    fk = foreign_keys("careers").find { |f| f.column == "competition_id" }
    assert_not_nil fk, "FK careers.competition_id is missing"
    assert_equal "competitions", fk.to_table.to_s, "FK must point at competitions"

    assert_includes index_names("careers"), "index_careers_on_competition_id"
  end

  test "careers has last_refreshed_at datetime with index" do
    assert_equal :datetime, columns("careers")["last_refreshed_at"]&.type
    assert_includes index_names("careers"), "index_careers_on_last_refreshed_at"
  end

  # ---- no minutes_played (T1 + brief must-not-do) ----

  test "no minutes_played column on players, football_teams, careers or competitions" do
    %w[players football_teams careers competitions].each do |table|
      assert_not_includes columns(table).keys, "minutes_played", "#{table} must not have minutes_played"
    end
  end

  test "schema.rb has new columns and no minutes_played" do
    schema = File.read(Rails.root.join("db/schema.rb"))
    %w[dob nationality photo_url last_refreshed_at goals assists cards_yellow cards_red competition_id].each do |col|
      assert_includes schema, %("#{col}"), "db/schema.rb must mention #{col}"
    end
    assert_not_includes schema, "minutes_played", "db/schema.rb must not mention minutes_played"
  end

  # ---- functional edge cases (existing rows survive; links work) ----

  test "legacy-style player without new fields still saves" do
    player = Player.create!(name: "T1 Legacy Player", external_id: "t1-legacy-1")
    assert_nil player.dob
    assert_nil player.nationality
    assert_nil player.photo_url
    assert_nil player.last_refreshed_at
  end

  test "player profile fields and staleness marker round-trip" do
    player = Player.create!(
      name: "T1 Profile Player", external_id: "t1-profile-1",
      dob: Date.new(1998, 5, 11), nationality: "England",
      photo_url: "https://example.com/photo.png",
      last_refreshed_at: Time.current
    )
    player.reload
    assert_equal Date.new(1998, 5, 11), player.dob
    assert_equal "England", player.nationality
    assert_equal "https://example.com/photo.png", player.photo_url
    assert_not_nil player.last_refreshed_at
  end

  test "career without goals saves (nullable day-one) and defaults apply" do
    player = Player.create!(name: "T1 Career Player", external_id: "t1-career-1")
    team = t1_team("T1 FC")
    career = Career.create!(
      player: player, football_team: team,
      duration: Date.new(2020, 7, 1)...Date.new(2021, 7, 1)
    )
    # goals may be nil (legacy) or 0 (default); both must be accepted pre-T6
    assert_includes [nil, 0], career.goals
    assert_nil career.assists
    assert_nil career.competition_id
    assert_nil career.last_refreshed_at
  end

  test "career stats and competition link persist" do
    country = t1_country
    competition = Competition.find_or_create_by!(name: "T1 Premier League") do |c|
      c.country = country
    end
    player = Player.create!(name: "T1 Stats Player", external_id: "t1-stats-1")
    team = t1_team("T1 United")
    career = Career.create!(
      player: player, football_team: team, competition_id: competition.id,
      duration: Date.new(2021, 7, 1)...Date.new(2022, 7, 1),
      goals: 12, assists: 7, cards_yellow: 3, cards_red: 1,
      last_refreshed_at: Time.current
    )
    career.reload
    assert_equal 12, career.goals
    assert_equal 7, career.assists
    assert_equal 3, career.cards_yellow
    assert_equal 1, career.cards_red
    assert_equal competition.id, career.competition_id
    assert_not_nil career.last_refreshed_at
  end

  test "career with unknown competition_id is rejected by fk" do
    player = Player.create!(name: "T1 FK Player", external_id: "t1-fk-1")
    team = t1_team("T1 Rovers")
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Career.create!(
        player: player, football_team: team, competition_id: 9_999_999_999,
        duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1), goals: 1
      )
    end
  end

  test "last_refreshed_at writable on football_teams" do
    team = t1_team("T1 Stale FC")
    team.update!(last_refreshed_at: 40.days.ago)
    assert_not_nil team.reload.last_refreshed_at
  end
end

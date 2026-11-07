# L5: Per-season coverage gate over the live-only YML allowlist.
#
# Read-only: prints per-season completeness and exits 0 only when there is
# zero missing data in the retrieved window. Never fetches or heals.
#
# Scoping note: the schema has no per-season membership column (T1 added none),
# so `season` labels the report and drives dead/partial flags from the
# per-league probe YML (`config/allowlist_<league_id>.yml`); missing-data
# counts are computed over the league's retrieved window in the DB
# (competition looked up by the passed league_id, default 39).
#
# Gate: PASS when teams-without-players == 0 AND players-without-careers == 0.
# A dead-listed season is listed, not counted as missing, so it passes even
# with gaps. "Senior" players (total career appearances >= 1) are kept in the
# DB, excluded from quiz candidacy, and reported by name only.
class CoverageGate < ApplicationService
  SENIOR_APPS_THRESHOLD = 1

  Report = Struct.new(
    :league_id, :season,
    :team_count, :teams_without_players,
    :players_in_scope, :players_without_careers,
    :senior_players,
    :dead, :dead_reason, :partial, :partial_detail, :allowlisted,
    :competition_missing,
    keyword_init: true
  ) do
    def pass?
      return true if dead
      return false if competition_missing
      teams_without_players.empty? && players_without_careers.empty?
    end

    def lines
      out = []
      out << "coverage league=#{league_id} season=#{season}"
      out << "competition_missing=true" if competition_missing
      out << "teams=#{team_count}"
      out << "teams_without_players=#{teams_without_players.size}"
      teams_without_players.each do |team|
        out << "team_without_players id=#{team.id} external_id=#{team.external_id} name=#{team.name}"
      end
      out << "players_in_scope=#{players_in_scope}"
      out << "players_without_careers=#{players_without_careers.size}"
      players_without_careers.each do |player|
        out << "player_without_career id=#{player.id} external_id=#{player.external_id} name=#{player.name}"
      end
      if dead
        out << "dead=true reason=#{dead_reason}"
      else
        out << "dead=false"
      end
      case partial
      when true then out << "partial=true #{partial_detail}"
      when false then out << "partial=false #{partial_detail}"
      else out << "partial=unknown #{partial_detail}"
      end
      case allowlisted
      when true then out << "allowlisted=true"
      when false then out << "allowlisted=false"
      else out << "allowlisted=unknown"
      end
      out << "senior_players_total_apps_ge1=#{senior_players.size}"
      senior_players.each do |senior|
        out << "senior_player name=#{senior[:name]} external_id=#{senior[:external_id]} total_apps=#{senior[:total_apps]}"
      end
      out << "coverage=#{pass? ? 'PASS' : 'FAIL'}"
      out
    end
  end

  def initialize(league_id: 39, season: Time.zone.now.year, config_dir: Rails.root.join("config"))
    @league_id = league_id.to_i
    @season = season.to_i
    @config_dir = Pathname.new(config_dir.to_s)
  end

  def call
    competition = Competition.find_by(external_id: @league_id.to_s)
    teams = competition ? competition.football_teams.distinct.order(:name) : FootballTeam.none

    missing_teams = teams.left_joins(:careers).where(careers: { id: nil })
    # NB: drop the listing ORDER BY inside id subqueries — Postgres rejects
    # SELECT DISTINCT id ... ORDER BY name.
    team_ids = teams.except(:order).select(:id)
    in_scope_count = Player.distinct.joins(:careers).where(careers: { football_team_id: team_ids }).count
    missing_players = Player.left_joins(:careers).where(careers: { id: nil }).order(:name)
    seniors = senior_list(teams, team_ids)

    dead_entry = dead_entry_for_season
    dead = !dead_entry.nil?
    if dead
      partial = false
      partial_detail = "dead season (listed, not counted as missing)"
    else
      partial, partial_detail = partial_for_season(teams.count)
    end

    Report.new(
      league_id: @league_id,
      season: @season,
      team_count: teams.count,
      teams_without_players: missing_teams.to_a,
      players_in_scope: in_scope_count,
      players_without_careers: missing_players.to_a,
      senior_players: seniors,
      dead: dead,
      dead_reason: dead_entry&.fetch(:reason, nil),
      partial: partial,
      partial_detail: partial_detail,
      allowlisted: allowlisted_for_season,
      competition_missing: competition.nil?
    )
  end

  private

  # Total career appearances summed per player over in-scope careers.
  # Kept in DB, excluded from quiz candidacy, reported by name only.
  def senior_list(teams, team_ids)
    return [] if teams.none?

    Player.joins(:careers)
      .where(careers: { football_team_id: team_ids })
      .group("players.id", "players.name", "players.external_id")
      .having(Arel.sql("SUM(COALESCE(careers.appearances, 0)) >= ?"), SENIOR_APPS_THRESHOLD)
      .order("players.name")
      .pluck("players.name", "players.external_id", Arel.sql("SUM(COALESCE(careers.appearances, 0))"))
      .map { |name, external_id, total| { name: name, external_id: external_id, total_apps: total.to_i } }
  end

  def yml_path
    Pl39Probe.allowlist_yml_path_for(@league_id, config_dir: @config_dir)
  end

  def yml_data
    Pl39Probe.read_yml(yml_path)
  end

  def yml_present?
    File.exist?(yml_path.to_s) && !yml_data.empty?
  end

  def dead_entry_for_season
    Pl39Probe.read_dead_yml(yml_path).find { |entry| entry[:season] == @season }
  end

  def allowlisted_for_season
    return nil unless yml_present?

    Pl39Probe.read_allowlist_yml(yml_path).include?(@season)
  end

  # Partial = probed ok by the probe but fewer teams retrieved in DB than the API listed.
  def partial_for_season(db_team_count)
    yml = yml_data
    return [ nil, "no #{Pl39Probe.allowlist_yml_filename_for(@league_id)}" ] if yml.empty?

    seasons = yml["seasons"] || yml[:seasons] || {}
    info = seasons[@season.to_s]
    return [ nil, "season not probed" ] if info.nil?

    status = info["status"] || info[:status]
    return [ nil, "probed #{status}" ] unless status == "ok"

    probed = (info["team_count"] || info[:team_count]).to_i
    if db_team_count < probed
      [ true, "db_teams=#{db_team_count} probed=#{probed}" ]
    else
      [ false, "db_teams=#{db_team_count} probed=#{probed}" ]
    end
  end
end

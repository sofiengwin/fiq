require "yaml"

# L2: live-only P1 probe — gates backfill on league seasons that have data.
#
# Starting from the present season and stepping back, asks the live-only
# FootballClient for `teams?league=<id>&season=<S>` and records the
# per-season team count. At most `max_requests` (default 10) live HTTP
# requests per run. Every run hits the API (no response cache); reruns are
# full-cost but idempotent (same memo rows for the same window/results).
#
# Scope store (DB-backed): one `league_seasons` memo row per contacted
# season (status ok/dead + team_count + checked_at). Rows persist across
# runs, so repeated <=10-request runs (or successive years) build the full
# retrievable window over time. Backfill refuses fresh-dead memos and any
# season outside the convention range [2010, present]; coverage reads
# dead/partial flags from the memos.
#
# Deprecated fallback: the `read_*_yml` readers below still parse the old
# committed `config/allowlist_<id>.yml` artifacts when no memo rows exist
# for a league (backfill/coverage consult them then). The probe no longer
# writes YML.
class LeagueProbe < ApplicationService
  LEAGUE_ID = 39
  MAX_LIVE_REQUESTS = 10

  # Deprecated fallback artifact: one YML per league under config_dir.
  def self.allowlist_yml_filename_for(league_id)
    "allowlist_#{league_id.to_i}.yml"
  end

  def self.allowlist_yml_path_for(league_id, config_dir: Rails.root.join("config"))
    Pathname.new(config_dir.to_s).join(allowlist_yml_filename_for(league_id))
  end

  # Minimal readers over the deprecated YML artifact (string-or-symbol
  # tolerant). Used only when no league_seasons memo rows exist.
  def self.read_allowlist_yml(path)
    data = read_yml(path)
    Array(data["allowlist"] || data[:allowlist]).map { |season| season.to_i }.sort
  end

  def self.read_dead_yml(path)
    data = read_yml(path)
    Array(data["dead"] || data[:dead]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      season = entry["season"] || entry[:season]
      reason = entry["reason"] || entry[:reason]
      next if season.nil?

      { season: season.to_i, reason: reason.to_s }
    end.sort_by { |entry| entry[:season] }
  end

  def self.read_yml(path)
    return {} unless File.exist?(path.to_s)

    YAML.safe_load(File.read(path.to_s)) || {}
  rescue Psych::SyntaxError
    {}
  end

  def initialize(league_id: LEAGUE_ID, present_year: Time.zone.now.year, max_requests: MAX_LIVE_REQUESTS,
    config_dir: Rails.root.join("config"))
    @league_id = league_id.to_i
    @present_year = present_year
    @max_requests = max_requests
    @config_dir = Pathname.new(config_dir.to_s)
  end

  def call
    probed = probe_window

    probed.each do |season, info|
      LeagueSeason.record_contact!(
        league_id: @league_id, season: season,
        status: info[:status], team_count: info[:team_count], reason: info[:reason]
      )
    end

    allowlist = LeagueSeason.ok_seasons_for(@league_id, present_year: @present_year)
    dead = LeagueSeason.dead_entries_for(@league_id)

    oldest_tried = probed.keys.min
    window_truncated = !oldest_tried.nil? && probed[oldest_tried][:status] == "ok"

    live_requests = probed.size
    Rails.logger.info(
      "LeagueProbe league=#{@league_id}: seasons_tried=#{probed.size} allowlisted=#{allowlist.size} " \
      "dead=#{dead.size} live_requests=#{live_requests} window_truncated=#{window_truncated}"
    )

    { league_id: @league_id, live_requests: live_requests, allowlist: allowlist, dead: dead, window_truncated: window_truncated }
  end

  private

  # One live request per season in the window (live-only: no cache check, so
  # live_requests always equals the window size, capped at @max_requests).
  def probe_window
    probed = {}
    @present_year.downto(@present_year - @max_requests + 1) do |season|
      begin
        teams = FootballClient.call(end_point: "teams?league=#{@league_id}&season=#{season}")
      rescue StandardError => e
        probed[season] = { status: "dead", team_count: 0, reason: "api error: #{e.message}" }
        next
      end

      if teams.is_a?(Array) && teams.size.positive?
        probed[season] = { status: "ok", team_count: teams.size }
      else
        reason = teams.is_a?(Array) ? "empty teams response" : "unexpected payload shape"
        probed[season] = { status: "dead", team_count: 0, reason: reason }
      end

      break if probed.size >= @max_requests
    end
    probed
  end
end

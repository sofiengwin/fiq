# frozen_string_literal: true

require "test_helper"

# BackfillLeagueJob: enqueued entry point for LeagueBackfill (see the
# data:backfill_league rake, which always enqueues). Pins the team_sync
# queue, the rate-limit retry, and delegation with the same args (service
# behavior itself is covered in LeagueBackfillTest).
class BackfillLeagueJobTest < ActiveSupport::TestCase
  include WebMock::API

  SEASON = 2022

  setup do
    WebMock.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
  end

  test "runs on the team_sync queue" do
    assert_equal "team_sync", BackfillLeagueJob.new.queue_name
  end

  test "delegates to LeagueBackfill with the same args and records the memo" do
    assert_nil LeagueSeason.memo_for(39, SEASON)
    stub_teams(SEASON, [ { id: 33, name: "Job Arsenal FC" } ])
    stub_players(33, SEASON, 1, [ { id: 101, name: "Job Player One" } ])
    stub_players_empty(33, SEASON, 2)

    result = BackfillLeagueJob.perform_now(39, SEASON)

    assert_equal :completed, result[:status]
    assert_equal "ok", LeagueSeason.memo_for(39, SEASON).status
    assert_equal 1, FootballTeam.where(external_id: "33").count
  end

  private

  def stub_teams(season, teams)
    body = {
      response: teams.map do |team|
        { team: { id: team[:id], name: team[:name], code: "C#{team[:id]}",
                  country: "England", national: false } }
      end,
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/teams?league=39&season=#{season}")
      .to_return(status: 200, body: body)
  end

  def stub_players(team_id, season, page, players)
    body = {
      response: players.map do |player|
        {
          player: {
            id: player[:id], name: player[:name],
            birth: { date: "1995-06-15" }, nationality: "England",
            photo: "https://example.com/#{player[:id]}.png"
          },
          statistics: [
            {
              team: { id: team_id }, league: { id: 39 },
              goals: { total: 3, assists: 2 },
              cards: { yellow: 1, red: 0 }
            }
          ]
        }
      end,
      paging: { current: page, total: 1 },
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/players?team=#{team_id}&season=#{season}&page=#{page}")
      .to_return(status: 200, body: body)
  end

  def stub_players_empty(team_id, season, page)
    body = {
      response: [],
      paging: { current: page, total: page },
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/players?team=#{team_id}&season=#{season}&page=#{page}")
      .to_return(status: 200, body: body)
  end
end

require "test_helper"
require "tmpdir"
require "yaml"

# L7 — Country alias config/country_aliases.yml: normalize-only + fork report.
#   - seeded aliases resolve case-insensitively to canonical names with no warn
#   - unmatched raw names still create a Country row verbatim + `alias_missing` warn
#   - blank maps to Unknown without warning; missing YML keeps raw + warns
#   - forks (distinct rows, one canonical) are reported by CoverageGate but do
#     not fail the gate (report-only; curation happens outside the pipeline)
class CountryAliasTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.reset!
    FootballClient.reset_throttle!
    @original_env = ENV.to_h.slice(FootballClient::THROTTLE_ENV_VAR)
    ENV[FootballClient::THROTTLE_ENV_VAR] = "0"
    @config_dir = Dir.mktmpdir
    write_aliases_yml("brasil" => "Brazil", "england" => "England")
  end

  teardown do
    WebMock.reset!
    FootballClient.reset_throttle!
    ENV.delete(FootballClient::THROTTLE_ENV_VAR)
    @original_env.each { |k, v| ENV[k] = v }
    FileUtils.remove_entry(@config_dir)
    CountryAlias.reset!
  end

  test "seeded aliases resolve case-insensitively with no warning" do
    assert_equal "Brazil", CountryAlias.canonical_for("Brasil", config_dir: @config_dir)
    assert_equal "Brazil", CountryAlias.canonical_for("BRASIL", config_dir: @config_dir)
    assert_equal "Brazil", CountryAlias.canonical_for("  brasil  ", config_dir: @config_dir)
    assert CountryAlias.matched?("Brasil", config_dir: @config_dir)

    logs = capture_logs do
      country = CountryAlias.find_or_create!("Brasil", config_dir: @config_dir)
      assert_equal "Brazil", country.name
      assert_equal country.id, CountryAlias.find_or_create!("Brazil", config_dir: @config_dir).id
    end
    assert_not_includes logs, "alias_missing"
  end

  test "already-canonical names resolve without warning" do
    logs = capture_logs do
      country = CountryAlias.find_or_create!("England", config_dir: @config_dir)
      assert_equal "England", country.name
    end
    assert_not_includes logs, "alias_missing"
  end

  test "unmatched raw name is kept verbatim and warns alias_missing" do
    logs = capture_logs do
      country = CountryAlias.find_or_create!("L7 Atlantis", config_dir: @config_dir)
      assert_equal "L7 Atlantis", country.name
    end
    assert_includes logs, "alias_missing"
    assert_includes logs, "L7 Atlantis"
  end

  test "blank maps to Unknown without warning" do
    logs = capture_logs do
      assert_equal "Unknown", CountryAlias.find_or_create!(nil, config_dir: @config_dir).name
      assert_equal "Unknown", CountryAlias.find_or_create!("  ", config_dir: @config_dir).name
    end
    assert_not_includes logs, "alias_missing"
  end

  test "missing YML keeps raw names verbatim with a warning" do
    empty_dir = Dir.mktmpdir
    begin
      logs = capture_logs do
        country = CountryAlias.find_or_create!("L7 Nowhere", config_dir: empty_dir)
        assert_equal "L7 Nowhere", country.name
      end
      assert_includes logs, "alias_missing"
    ensure
      FileUtils.remove_entry(empty_dir)
    end
  end

  test "forks lists distinct rows that normalize to one canonical" do
    Country.create!(name: "Brazil")
    Country.create!(name: "Brasil")

    forks = CountryAlias.forks

    assert_equal 1, forks.size
    assert_equal "Brazil", forks.first[:canonical]
    assert_equal %w[Brasil Brazil], forks.first[:names]
  end

  test "no forks when countries are already canonical" do
    Country.create!(name: "L7 Canonical Only #{SecureRandom.hex(4)}")

    assert_empty CountryAlias.forks
  end

  test "coverage report lists alias forks but still passes" do
    country = Country.create!(name: "L7 Hostland #{SecureRandom.hex(4)}")
    competition = Competition.create!(
      name: "L7 League", external_id: "39701", country: country
    )
    team = FootballTeam.create!(name: "L7 Fork FC", country: country)
    competition.football_teams << team
    player = Player.create!(name: "L7 Fork Player", external_id: "l7-#{SecureRandom.hex(4)}")
    Career.create!(
      player: player, football_team: team,
      duration: Date.new(2022, 7, 1)...Date.new(2023, 7, 1), appearances: 2
    )
    Country.create!(name: "Brazil")
    Country.create!(name: "Brasil")

    report = CoverageGate.call(league_id: 39701, season: 2022, config_dir: @config_dir)

    assert report.pass?
    lines = report.lines.join("\n")
    assert_includes lines, "alias_forks=1"
    assert_includes lines, "alias_fork canonical=Brazil names=Brasil,Brazil"
    assert_includes lines, "coverage=PASS"
  end

  test "upsert league teams normalizes the country through the alias map" do
    body = {
      response: [
        { team: { id: 397001, name: "L7 Brasil FC", code: "L7B", country: "Brasil", national: false } }
      ],
      errors: {}
    }.to_json
    stub_request(:get, "https://v3.football.api-sports.io/teams?league=39&season=2022")
      .to_return(status: 200, body: body)

    UpsertLeagueTeams.call(league_id: 39, season: 2022, competition_name: "L7 Premier League")

    team = FootballTeam.find_by!(external_id: 397001)
    assert_equal "Brazil", team.country.name
  end

  private

  def write_aliases_yml(aliases)
    File.write(
      File.join(@config_dir, "country_aliases.yml"),
      YAML.dump({ "aliases" => aliases })
    )
  end

  def capture_logs
    io = StringIO.new
    old_logger = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old_logger
  end
end

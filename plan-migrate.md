# FIQ Recreation Plan

A comprehensive guide to recreate the Football Career Journey Tracker in a new Rails project.

> **⚠️ IMPORTANT**: This plan adds a Football Career Tracker to the existing quiz application. 
> The existing quiz functionality will remain intact. New models, services, and jobs will be added alongside.

---

## Pre-Implementation Notes

### Compatibility with Existing Project

The current project is a **Kahoot-style quiz app** with:
- Existing models: Quiz, Question, AnswerOption, QuizAttempt, Response, ResponseAnswer
- Existing gems: tailwindcss-rails, turbo-rails, stimulus-rails, solid_queue, solid_cache

### Changes Required for Integration

1. **Background Jobs**: The project already uses `solid_queue` (Rails 8 default). We'll use that instead of GoodJob.
2. **Database**: Already configured with PostgreSQL - compatible with daterange type.
3. **Admin UI**: Will add ActiveAdmin alongside existing controllers.
4. **Docker**: Already configured - will extend existing docker-compose.yml.

### New Dependencies to Add
```ruby
# Add to Gemfile
gem "ruby-limiter"           # Rate limiting for API calls
gem "activeadmin", "~> 3.2"  # Admin UI
gem "sassc-rails"            # Required for ActiveAdmin styles
gem "devise"                 # Admin authentication
```

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Database Schema & Migrations](#2-database-schema--migrations)
3. [Models & Associations](#3-models--associations)
4. [Service Layer Architecture](#4-service-layer-architecture)
5. [External API Integration](#5-external-api-integration)
6. [Background Job System (solid_queue)](#6-background-job-system-solid_queue)
7. [Worker Chain Pattern](#7-worker-chain-pattern)
8. [Admin Interface (ActiveAdmin)](#8-admin-interface-activeadmin)
9. [Docker Configuration](#9-docker-configuration)
10. [Testing with VCR](#10-testing-with-vcr)
11. [Date Range Handling](#11-date-range-handling)
12. [Credentials & Environment Variables](#12-credentials--environment-variables)

---

## 1. Project Setup

### Required Gems (Gemfile)

Add these gems to the existing Gemfile (don't replace the existing gems):

```ruby
# Add to existing Gemfile

# Rate Limiting for API calls
gem "ruby-limiter"

# Admin UI
gem "activeadmin", "~> 3.2"
gem "sassc-rails"  # Required for ActiveAdmin styles
gem "devise"           # For admin authentication

# Logging (optional, but recommended)
gem "lograge"

group :development, :test do
  gem "vcr"
  gem "webmock"
end
```

**Note**: The project already has `solid_queue` for background jobs - we'll use that instead of GoodJob.

Run:
```bash
docker compose run --rm web bundle install
```

---

## 2. Database Schema & Migrations

### Migration 1: Create Countries

```bash
docker compose run --rm web bin/rails g migration CreateCountries name:string code:string
```

```ruby
class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :code
      t.timestamps
    end
    add_index :countries, :name, unique: true
  end
end
```

### Migration 2: Create FootballTeams

**Note**: Using `FootballTeam` to avoid conflict with any future "Team" model for quiz teams.

```bash
docker compose run --rm web bin/rails g migration CreateFootballTeams name:string code:string external_id:string country:references
```

```ruby
class CreateFootballTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :football_teams do |t|
      t.string :name, null: false
      t.string :code
      t.string :external_id
      t.references :country, foreign_key: true
      t.timestamps
    end
    add_index :football_teams, :external_id, unique: true
  end
end
```

### Migration 3: Create Competitions

```bash
docker compose run --rm web bin/rails g migration CreateCompetitions name:string external_id:string country:references
```

```ruby
class CreateCompetitions < ActiveRecord::Migration[8.1]
  def change
    create_table :competitions do |t|
      t.string :name, null: false
      t.string :external_id
      t.references :country, foreign_key: true
      t.timestamps
    end
    add_index :competitions, :external_id, unique: true
  end
end
```

### Migration 4: Create Competitions-FootballTeams Join Table

```bash
docker compose run --rm web bin/rails g migration CreateCompetitionsFootballTeams
```

```ruby
class CreateCompetitionsFootballTeams < ActiveRecord::Migration[8.1]
  def change
    create_join_table :competitions, :football_teams do |t|
      t.index [:competition_id, :football_team_id], name: "idx_comp_team"
      t.index [:football_team_id, :competition_id], name: "idx_team_comp"
    end
  end
end
```

### Migration 5: Create Players

```bash
docker compose run --rm web bin/rails g migration CreatePlayers name:string first_name:string last_name:string external_id:string position:string age:integer appearances:integer
```

```ruby
class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.string :name, null: false
      t.string :first_name
      t.string :last_name
      t.string :external_id
      t.string :position
      t.integer :age
      t.integer :appearances, default: 0
      t.timestamps
    end
    add_index :players, :external_id, unique: true
  end
end
```

### Migration 6: Create Careers (with DateRange)

```bash
docker compose run --rm web bin/rails g migration CreateCareers player:references football_team:references
```

```ruby
class CreateCareers < ActiveRecord::Migration[8.1]
  def change
    create_table :careers do |t|
      t.references :player, null: false, foreign_key: true
      t.references :football_team, null: false, foreign_key: true
      t.daterange :duration  # PostgreSQL DateRange type
      t.timestamps
    end
    
    # Index for overlapping career queries
    add_index :careers, :duration, using: :gist
  end
end
```

Run all migrations:
```bash
docker compose run --rm web bin/rails db:migrate
```

---

## 3. Models & Associations

### app/models/country.rb

```ruby
class Country < ApplicationRecord
  has_many :football_teams, dependent: :destroy
  has_many :competitions, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  # Configuration constant for leagues to track
  START = {
    "England" => {
      "English Premier League" => {
        league_id: 39,  # Corrected API league ID for Premier League
        season: 2020
      }
    },
    "Spain" => {
      "La Liga" => {
        league_id: 140,  # Corrected API league ID for La Liga
        season: 2023
      }
    },
    "France" => {
      "Ligue 1" => {
        league_id: 61,  # Corrected API league ID for Ligue 1
        season: 2023
      }
    },
    "Germany" => {
      "Bundesliga" => {
        league_id: 78,  # Corrected API league ID for Bundesliga
        season: 2023
      }
    },
    "Italy" => {
      "Serie A" => {
        league_id: 135,  # Corrected API league ID for Serie A
        season: 2023
      }
    }
  }.freeze
end
```

### app/models/football_team.rb

```ruby
class FootballTeam < ApplicationRecord
  belongs_to :country
  has_many :careers, dependent: :destroy
  has_many :players, through: :careers
  has_and_belongs_to_many :competitions

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  def players_count
    players.distinct.count
  end

  def fetch_data
    FetchTeamPlayersJob.perform_later(id)
  end
end
```
  has_many :careers
  has_many :players, through: :careers
  has_and_belongs_to_many :competitions

  def players_count
    players.count
  end

  def fetch_data
    FetchTeamPlayersJob.perform_later(self.id)
  end
end
```

### app/models/competition.rb

```ruby
class Competition < ApplicationRecord
  belongs_to :country
  has_and_belongs_to_many :football_teams

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true
end
```

### app/models/player.rb

```ruby
class Player < ApplicationRecord
  has_many :careers, dependent: :destroy
  has_many :football_teams, through: :careers

  validates :name, presence: true
  validates :external_id, uniqueness: true, allow_nil: true

  def journey
    careers.includes(:football_team).order("careers.duration").map { |career|
      team_name = career.football_team.name
      duration = format_duration(career.duration)
      "#{team_name} :: #{duration}"
    }.join("<br><br>")
  end

  def fetch_data
    FetchPlayerCareerJob.perform_later(id, nil)
  end

  private

  def format_duration(range)
    start_date = range.begin&.strftime("%Y") || "?"
    end_date = range.end&.strftime("%Y") || "Present"
    "#{start_date} - #{end_date}"
  end
end
```

### app/models/career.rb

```ruby
class Career < ApplicationRecord
  belongs_to :player
  belongs_to :football_team

  validates :duration, presence: true
  validate :no_overlapping_careers

  # Scope to find teammates with overlapping careers
  scope :overlapping_teammates, ->(min_years: 2) {
    joins(%(
      INNER JOIN careers c2 ON careers.football_team_id = c2.football_team_id
      AND careers.player_id < c2.player_id
      AND careers.duration && c2.duration
    ))
    .where(%(
      EXTRACT(YEAR FROM AGE(
        LEAST(UPPER(careers.duration), UPPER(c2.duration)),
        GREATEST(LOWER(careers.duration), LOWER(c2.duration))
      )) >= ?
    ), min_years)
  }

  # Find careers that overlap with a given date range
  scope :overlapping_with, ->(date_range) {
    where("duration && ?::daterange", "[#{date_range.begin},#{date_range.end})")
  }

  private

  def no_overlapping_careers
    return unless player && duration

    overlapping = player.careers
      .where.not(id: id)
      .where("duration && ?::daterange", "[#{duration.begin},#{duration.end})")

    if overlapping.exists?
      errors.add(:duration, "overlaps with an existing career")
    end
  end
end
```

---

## 4. Service Layer Architecture

### Base Service Class

The project already has `app/services/score_calculator.rb`. Create a base class:

```ruby
# app/services/application_service.rb
class ApplicationService
  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError, "Subclasses must implement #call"
  end
end
```

**Convention:**
- Instantiate with named params: `Service.new(param: value)`
- Call via class method: `Service.call(param: value)`
- Always implement `#call` method returning primary result

**Note:** Update the existing `ScoreCalculator` to inherit from `ApplicationService` if desired.

---

## 5. External API Integration

### app/services/football_client.rb

```ruby
require "uri"
require "net/http"
require "openssl"

class FootballClient < ApplicationService
  extend Limiter::Mixin

  # Rate limit: 300 requests per minute
  limit_method(:call, rate: 300, interval: 60, balanced: true) do
    Rails.logger.info("FootballClient rate limit exceeded")
    raise StandardError, "Rate limit exceeded"
  end

  BASE_URL = "https://v3.football.api-sports.io/"

  def initialize(end_point:)
    @end_point = end_point
    @url = URI("#{BASE_URL}#{@end_point}")
  end

  def call
    response = JSON.parse(make_request.body, symbolize_names: true)
    raise StandardError, response[:error] if response[:error]
    response[:response]
  rescue StandardError => e
    Rails.logger.error("FootballClient Error: #{e.message}")
    raise e
  end

  private

  def make_request
    request = Net::HTTP::Get.new(@url)
    request["x-rapidapi-host"] = Rails.application.credentials.dig(:football_api, :host)
    request["x-rapidapi-key"] = Rails.application.credentials.dig(:football_api, :api_key)

    Net::HTTP.start(@url.hostname, @url.port, use_ssl: true) do |http|
      http.request(request)
    end
  end
end
```

### Service Objects

#### app/services/upsert_league_teams.rb

```ruby
class UpsertLeagueTeams < ApplicationService
  def initialize(league_id:, season:, competition_name:)
    @league_id = league_id
    @season = season
    @competition_name = competition_name
  end

  def call
    result = fetch_teams
    result.map do |team|
      UpsertTeam.call(
        external_id: team[:team][:id],
        name: team[:team][:name],
        code: team[:team][:code],
        country: country(name: team[:team][:country]),
        competition: competition
      )
    end
  end

  private

  def fetch_teams
    FootballClient.call(end_point: "teams?league=#{@league_id}&season=#{@season}")
  end

  def country(name:)
    @country ||= Country.find_or_create_by!(name: name)
  end

  def competition
    return nil if @league_id.blank?
    Competition.find_or_create_by!(external_id: @league_id) do |c|
      c.name = @competition_name
      c.country_id = @country.id
    end
  end
end
```

#### app/services/upsert_team.rb

```ruby
class UpsertTeam < ApplicationService
  def initialize(external_id:, name:, code:, country:, competition: nil)
    @external_id = external_id
    @name = name
    @code = code
    @country = country
    @competition = competition
  end

  def call
    team = FootballTeam.find_or_create_by!(external_id: @external_id) do |t|
      t.name = @name
      t.code = @code
      t.country_id = @country.id
    end
    
    if @competition && !team.competitions.include?(@competition)
      team.competitions << @competition
    end
    
    team
  end
end
```
  end
end
```

#### app/services/upsert_team_players.rb

```ruby
class UpsertTeamPlayers < ApplicationService
  def initialize(team:)
    @team = team
  end

  def call
    response = fetch_players
    return [] if response.blank? || response[0].nil?

    players_data = response[0][:players]
    return [] if players_data.blank?

    players_data.map do |player_params|
      player = Player.find_or_create_by(external_id: player_params[:id]) do |p|
        p.name = player_params[:name]
        p.position = player_params[:position]
        p.age = player_params[:age]
      end
      
      # Create initial career entry if not exists
      unless player.careers.exists?(football_team: @team)
        player.careers.create(
          football_team: @team,
          duration: Date.current..nil  # Open-ended (current team)
        )
      end
      
      player
    end
  end

  private

  def fetch_players
    FootballClient.call(end_point: "players/squads?team=#{@team.external_id}")
  end
end
```

#### app/services/upsert_player_career.rb

```ruby
class UpsertPlayerCareer < ApplicationService
  def initialize(player:, team: nil)
    @player = player
    @team = team
  end

  def call
    player_career = fetch_player_transfers
    return if player_career.blank? || player_career[0].nil?

    transfers = player_career[0][:transfers]
    return if transfers.blank?

    sorted_transfers = transfers.sort_by { |t| t[:date] }
    fmt_transfers = format_transfers(sorted_transfers)
    merged_transfers = merge_consecutive_careers(fmt_transfers)

    # Clear existing careers
    @player.careers.destroy_all

    merged_transfers.each do |transfer|
      team = find_or_create_team(
        team_external_id: transfer[:id],
        team_name: transfer[:name]
      )
      next if team.nil? || transfer[:start_date].nil?

      @player.careers.create!(
        football_team_id: team.id,
        duration: transfer[:start_date]..transfer[:end_date]
      )
    end
    
    @player.careers.reload
  rescue StandardError => e
    Rails.logger.error("UpsertPlayerCareer failed for player #{@player.id}: #{e.message}")
    raise e
  end

  private

  def fetch_player_transfers
    FootballClient.call(end_point: "transfers?player=#{@player.external_id}")
  end

  def fetch_team_profile(team_id:)
    FootballClient.call(end_point: "teams?id=#{team_id}")
  end

  def find_or_create_team(team_external_id:, team_name:)
    existing_team = FootballTeam.find_by(external_id: team_external_id)
    return existing_team if existing_team.present?

    team_profile = fetch_team_profile(team_id: team_external_id)
    return nil if team_profile.blank? || team_profile[0].nil? || team_profile[0][:team].nil?

    team_data = team_profile[0][:team]
    UpsertTeam.call(
      external_id: team_external_id,
      name: team_data[:name],
      code: team_data[:code],
      country: country(name: team_data[:country])
    )
  end

  def fetch_active_seasons
    FootballClient.call(end_point: "players/seasons?player=#{@player.external_id}")
  end

  def format_transfers(transfers)
    fmt_transfers = []
    transfers.each_with_index do |transfer, index|
      destination_team = transfer[:teams][:in]
      next if destination_team.nil?

      start_date = fmt_date(transfer[:date])
      end_date = if index == transfers.length - 1
        latest_career_end_date
      else
        fmt_date(transfers[index + 1][:date])
      end

      next if end_date && start_date && end_date < start_date

      fmt_transfers << destination_team.merge(
        start_date: start_date,
        end_date: end_date
      )
    end
    fmt_transfers
  end

  def merge_consecutive_careers(transfers)
    return [] if transfers.empty?
    merged = []

    transfers.group_by { |t| t[:id] }.each do |_team_id, team_transfers|
      sorted = team_transfers.sort_by { |t| t[:start_date] }
      current = sorted.first.dup

      sorted[1..].each do |transfer|
        current_end = current[:end_date] || Date::Infinity.new
        transfer_start = transfer[:start_date]

        if transfer_start <= current_end + 1.day
          current[:end_date] = transfer[:end_date] if transfer[:end_date].nil? ||
            (current[:end_date] && transfer[:end_date] && transfer[:end_date] > current[:end_date])
        else
          merged << current
          current = transfer.dup
        end
      end
      merged << current
    end
    merged.sort_by { |t| t[:start_date] }
  end

  def latest_career_end_date
    active_seasons = fetch_active_seasons
    return nil if active_seasons.blank?
    
    if Time.zone.now.year >= active_seasons.last
      nil  # Still active
    else
      Date.new(active_seasons.last, 12, 31)
    end
  end

  def country(name:)
    Country.find_or_create_by!(name: name)
  end

  def fmt_date(date)
    date&.to_date
  rescue ArgumentError
    nil
  end
end
```

---

## 6. Background Job System (solid_queue)

**Note:** This project already has `solid_queue` configured (Rails 8 default). We'll use the existing setup instead of adding GoodJob.

solid_queue is a database-backed Active Job adapter that comes bundled with Rails 8. It uses your existing PostgreSQL database, so no Redis is required.

### Verify Existing Configuration

The project should already have:
- `config/queue.yml` - queue configuration
- `db/queue_schema.rb` - database schema for solid_queue

#### Verify config/application.rb

```ruby
module FiqFull
  class Application < Rails::Application
    # Rails 8 default - already configured
    config.active_job.queue_adapter = :solid_queue
  end
end
```

#### config/solid_queue.yml (verify or create)

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 1
      polling_interval: 0.1

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
  workers:
    - queues: "default,career_sync,team_sync"
      threads: 5
      processes: 2
      polling_interval: 0.1
```

#### Queue Configuration

Define custom queues for our jobs in Procfile.dev (optional for dev):

```
# Procfile.dev (jobs are already handled by solid_queue)
web: rm -f tmp/pids/server.pid && bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
```

For production, solid_queue runs automatically with `bin/jobs` or can be managed via:

```bash
# Production
bin/jobs  # Runs the solid_queue supervisor
```

---

## 7. Job Chain Pattern

The application uses a **chained job pattern** for incremental data ingestion:

```
LeagueTeamsJob → FetchTeamPlayersJob → FetchPlayerCareerJob
```

### app/jobs/league_teams_job.rb (Entry Point)

```ruby
class LeagueTeamsJob < ApplicationJob
  queue_as :team_sync

  def perform(external_league_id, season, competition_name)
    return if Time.zone.now.year < season

    teams = UpsertLeagueTeams.call(
      league_id: external_league_id,
      season: season,
      competition_name: competition_name
    )

    # Chain: queue player fetch for each team
    teams.each do |team|
      FetchTeamPlayersJob.perform_later(team.id)
    end

    # Recursively process next season
    LeagueTeamsJob.perform_later(
      external_league_id,
      season + 1,
      competition_name
    )
  rescue StandardError => e
    Rails.logger.error "LeagueTeamsJob failed: #{e.message}"
    raise
  end

  # Entry point to start ingestion
  def self.start_ingestion
    Country::START.each do |country, competitions|
      competitions.each do |competition, league|
        LeagueTeamsJob.perform_later(league[:league_id], league[:season], competition)
      end
    end
  end
end
```

### app/jobs/fetch_team_players_job.rb

```ruby
class FetchTeamPlayersJob < ApplicationJob
  queue_as :team_sync

  def perform(team_id)
    team = FootballTeam.find(team_id)
    players = UpsertTeamPlayers.call(team: team)

    # Chain: queue career fetch for each player
    players.each do |player|
      FetchPlayerCareerJob.perform_later(player.id, team_id)
    end
  end
end
```

### app/jobs/fetch_player_career_job.rb

```ruby
class FetchPlayerCareerJob < ApplicationJob
  queue_as :career_sync

  def perform(player_id, team_id = nil)
    player = Player.find(player_id)
    UpsertPlayerCareer.call(player: player)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "FetchPlayerCareerJob: Player #{player_id} not found"
    # Don't retry if record doesn't exist
  end
end
```

### app/jobs/application_job.rb (update existing)

```ruby
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encounter a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on API failures with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # Log job execution
  around_perform do |job, block|
    Rails.logger.info "[#{job.class.name}] Starting with args: #{job.arguments.inspect}"
    block.call
    Rails.logger.info "[#{job.class.name}] Completed successfully"
  rescue => e
    Rails.logger.error "[#{job.class.name}] Failed: #{e.message}"
    raise
  end
end
```

**Key Pattern:** Jobs only orchestrate. Business logic lives in Service objects.

---

## 8. Admin Interface (ActiveAdmin)

### Setup ActiveAdmin

```bash
rails g active_admin:install --skip-users
```

**Note:** We skip the default AdminUser since we'll use Devise separately or a custom auth approach.

### Generate Admin Resources

```bash
rails g active_admin:resource Country
rails g active_admin:resource FootballTeam
rails g active_admin:resource Competition
rails g active_admin:resource Player
rails g active_admin:resource Career
```

### app/admin/players.rb

```ruby
ActiveAdmin.register Player do
  permit_params :name, :position, :external_id

  # Custom action to fetch career data
  member_action :fetch_career, method: :post do
    resource.fetch_data
    redirect_to admin_player_path(resource), notice: "Career fetch job queued for #{resource.name}"
  end

  action_item :fetch_career, only: :show do
    link_to "Fetch Career", fetch_career_admin_player_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :position
    column :external_id
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :name
      row :position
      row :external_id
      row :journey do |player|
        player.journey.html_safe
      end
    end

    panel "Careers" do
      table_for resource.careers.includes(:football_team).order("duration DESC") do
        column :football_team
        column :duration do |career|
          "#{career.duration.begin} - #{career.duration.end || 'Present'}"
        end
      end
    end
  end

  filter :name
  filter :position
  filter :external_id
end
```

### app/admin/football_teams.rb

```ruby
ActiveAdmin.register FootballTeam do
  permit_params :name, :code, :external_id, :country_id, competition_ids: []

  # Custom action to fetch team players
  member_action :fetch_players, method: :post do
    FetchTeamPlayersJob.perform_later(resource.id)
    redirect_to admin_football_team_path(resource), notice: "Player fetch job queued for #{resource.name}"
  end

  action_item :fetch_players, only: :show do
    link_to "Fetch Players", fetch_players_admin_football_team_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :code
    column :country
    column :players_count do |team|
      team.players.count
    end
    actions
  end

  show do
    attributes_table do
      row :name
      row :code
      row :country
      row :external_id
      row :competitions do |team|
        team.competitions.map(&:name).join(", ")
      end
    end

    panel "Players (#{resource.players.count})" do
      table_for resource.players.limit(50) do
        column :name do |player|
          link_to player.name, admin_player_path(player)
        end
        column :position
      end
    end
  end

  filter :name
  filter :code
  filter :country
  filter :competitions
end
```

### app/admin/countries.rb

```ruby
ActiveAdmin.register Country do
  permit_params :name

  index do
    selectable_column
    id_column
    column :name
    column :teams_count do |country|
      country.football_teams.count
    end
    actions
  end

  filter :name
end
```

### app/admin/competitions.rb

```ruby
ActiveAdmin.register Competition do
  permit_params :name, :external_id, :country_id

  # Custom action to start league sync
  member_action :sync_teams, method: :post do
    LeagueTeamsJob.perform_later(resource.external_id, Time.zone.now.year, resource.name)
    redirect_to admin_competition_path(resource), notice: "Team sync job queued for #{resource.name}"
  end

  action_item :sync_teams, only: :show do
    link_to "Sync Teams", sync_teams_admin_competition_path(resource), method: :post
  end

  index do
    selectable_column
    id_column
    column :name
    column :country
    column :teams_count do |comp|
      comp.football_teams.count
    end
    actions
  end

  filter :name
  filter :country
end
```

### app/admin/dashboard.rb

```ruby
ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "Statistics" do
          ul do
            li "Countries: #{Country.count}"
            li "Teams: #{FootballTeam.count}"
            li "Players: #{Player.count}"
            li "Competitions: #{Competition.count}"
            li "Careers: #{Career.count}"
          end
        end
      end

      column do
        panel "Recent Players" do
          table_for Player.order(created_at: :desc).limit(10) do
            column :name do |player|
              link_to player.name, admin_player_path(player)
            end
            column :position
            column :created_at
          end
        end
      end
    end

    columns do
      column do
        panel "Start Data Ingestion" do
          para "Click to start fetching data for all configured leagues:"
          para link_to "Start Full Sync", start_sync_admin_dashboard_path, method: :post, class: "button"
        end
      end
    end
  end

  page_action :start_sync, method: :post do
    LeagueTeamsJob.start_ingestion
    redirect_to admin_dashboard_path, notice: "Data ingestion jobs have been queued!"
  end
end
```

### config/initializers/active_admin.rb (key settings)

```ruby
ActiveAdmin.setup do |config|
  config.site_title = "FIQ Football Admin"
  config.root_to = "dashboard#index"
  
  # Skip authentication for development (configure properly for production)
  config.authentication_method = false
  config.current_user_method = false
  
  # For production with Devise:
  # config.authentication_method = :authenticate_admin_user!
  # config.current_user_method = :current_admin_user
  # config.logout_link_path = :destroy_admin_user_session_path
  
  config.batch_actions = true
  config.filter_attributes = [:encrypted_password, :password, :password_confirmation]
  config.localize_format = :long
end
```

---

## 9. Docker Configuration

### Dockerfile

```dockerfile
ARG RUBY_VERSION=3.2.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="development" \
    BUNDLE_PATH="/usr/local/bundle"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
```

### docker-compose.yml Updates

**Note:** The project already has a working `docker-compose.yml`. For production with a separate job worker, add this service:

```yaml
# Add to existing docker-compose.yml for production job processing
services:
  # ... existing web and db services ...

  jobs:
    build:
      context: .
    volumes:
      - .:/rails
    command: bin/jobs
    env_file:
      - .env
    environment:
      - DATABASE_URL=postgres://postgres:password@db:5432/fiq_full_development
    depends_on:
      db:
        condition: service_healthy
      web:
        condition: service_started
```

**Note:** In development, solid_queue runs jobs inline or via the `bin/jobs` command. For production, add the `jobs` service above.

### bin/docker-entrypoint

```bash
#!/bin/bash -e

# If running the rails server, prepare database
if [ "${1}" == "./bin/rails" ] && [ "${2}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

---

## 10. Testing with VCR

### test/test_helper.rb

```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "vcr"

# Configure ActiveJob for inline execution in tests
ActiveJob::Base.queue_adapter = :test

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    
    # Include ActiveJob test helpers
    include ActiveJob::TestHelper
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock

  # Filter sensitive data
  config.filter_sensitive_data("<FOOTBALL_API_KEY>") do
    Rails.application.credentials.dig(:football_api, :api_key)
  end

  config.filter_sensitive_data("<FOOTBALL_API_HOST>") do
    Rails.application.credentials.dig(:football_api, :host)
  end
end
```

### Example Service Test

```ruby
# test/services/upsert_player_career_test.rb
require "test_helper"

class UpsertPlayerCareerTest < ActiveSupport::TestCase
  test "creates career records from transfers" do
    player = players(:sample_player)

    VCR.use_cassette("player/transfers_#{player.external_id}") do
      VCR.use_cassette("player/seasons_#{player.external_id}") do
        UpsertPlayerCareer.call(player: player)
      end
    end

    assert player.careers.any?
  end
end
```

**Directory Structure:**
```
test/fixtures/vcr_cassettes/
├── league/
├── player/
└── team/
```

---

## 11. Date Range Handling

### PostgreSQL DateRange Type

- `careers.duration` uses PostgreSQL's native `daterange` type
- **Open-ended ranges**: `nil` end_date for active careers
- **Query overlap**: Use `&&` operator

### Key Queries

```sql
-- Find overlapping careers for same player
SELECT * FROM careers c1
JOIN careers c2 ON c1.player_id = c2.player_id 
  AND c1.id < c2.id
  AND c1.duration && c2.duration;

-- Check if date falls within career
SELECT * FROM careers WHERE duration @> '2023-01-15'::date;
```

### ActiveRecord Usage

```ruby
# Create career with date range
Career.create!(
  player: player,
  team: team,
  duration: Date.new(2020, 1, 1)..Date.new(2023, 6, 30)
)

# Active career (no end date)
Career.create!(
  player: player,
  team: team,
  duration: Date.new(2023, 7, 1)..nil
)

# Query overlapping
Career.where("duration && ?", date_range)
```

---

## 12. Credentials & Environment Variables

### Rails Credentials

Store API keys securely:

```bash
EDITOR="code --wait" rails credentials:edit
```

```yaml
football_api:
  host: v3.football.api-sports.io
  api_key: your_api_key_here
```

### Environment Variables

Create `.env` file (or update existing):

```bash
DATABASE_URL=postgres://postgres:password@db:5432/fiq_full_development
RAILS_MASTER_KEY=<your_master_key>
FOOTBALL_API_KEY=<your_api_key>
```

**Note:** No Redis needed! solid_queue uses your existing PostgreSQL database.

### config/database.yml

**Note:** The project already has `database.yml` configured. No changes needed unless you want to add the test database:

```yaml
# Existing configuration should work. Verify test database:
test:
  <<: *default
  database: fiq_full_test
```

---

## Quick Start Commands

```bash
# Start all services
docker-compose up

# Access Rails console
docker-compose exec web bin/rails console

# Run migrations
docker-compose exec web bin/rails db:migrate

# Start data ingestion
docker-compose exec web bin/rails console
> LeagueTeamsJob.perform_later

# Run tests
docker-compose exec web bin/rails test
```

---

## Summary Checklist

**Gems to Add:**
- [ ] Add gems: ruby-limiter, activeadmin, sassc-rails, devise, vcr, webmock

**Database & Models:**
- [ ] Create migrations with daterange field for careers
- [ ] Set up models with associations (Country, FootballTeam, Competition, Player, Career)
- [ ] Add unique indexes for external_id fields

**Services:**
- [ ] Create ApplicationService base class
- [ ] Implement FootballClient with rate limiting
- [ ] Create service objects (UpsertLeagueTeams, UpsertTeam, UpsertTeamPlayers, UpsertPlayerCareer)

**Jobs (using existing solid_queue):**
- [ ] Create chained jobs (LeagueTeamsJob → FetchTeamPlayersJob → FetchPlayerCareerJob)
- [ ] Verify solid_queue is configured (should already be in Rails 8)

**Admin:**
- [ ] Run `rails g active_admin:install --skip-users`
- [ ] Generate admin resources for all models
- [ ] Configure custom actions (fetch_career, fetch_players, sync_teams)
- [ ] Set up Mission Control Jobs dashboard (optional - for job monitoring)

**Testing:**
- [ ] Configure VCR for API testing
- [ ] Store API credentials securely in credentials.yml.enc

**Verification:**
- [ ] Test the job chain with `LeagueTeamsJob.perform_later`

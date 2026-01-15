# FIQ - Football Career Journey Tracker

## Project Overview
FIQ is a Rails 8.1 API application that aggregates football player career data from the API-Football service. The system builds a comprehensive database of players, teams, competitions, and career histories across Europe's top 5 leagues (Premier League, La Liga, Ligue 1, Bundesliga, Serie A).

**Core Purpose**: Track player career journeys across clubs to enable queries about teammates, career paths, and club histories.

## Architecture

### Data Flow Chain
The application uses a **chained Sidekiq worker pattern** to incrementally build the database:

1. `LeagueTeamsWorker` → Fetches all teams in a league/season
2. `FetchTeamPlayersWorker` → Gets current squad for each team  
3. `FetchPlayerCareerWorker` → Retrieves complete career history for each player

**Entry Point**: `LeagueTeamsWorker.enqueue` (configured in `Country::START` constant)

### Service Layer Pattern
All business logic lives in service objects inheriting from `ApplicationService`:
- **Instantiate with named params**: `Service.new(param: value)`
- **Call via class method**: `Service.call(param: value)` 
- **Always implement `#call`**: Returns the primary result object(s)

Example: `UpsertPlayerCareer.call(player: player, team: team)`

### External API Integration
`FootballClient` wraps the API-Football v3 service:
- **Base URL**: `https://v3.football.api-sports.io/`
- **Authentication**: Hardcoded API key (see `FootballClient#make_request`)
- **Usage**: `FootballClient.call(end_point: "players/squads?team=33")`
- **Returns**: Parsed JSON response with `:response` key

### Models & Associations
```
Country 1:N Team N:M Competition
Player 1:N Career N:1 Team
```
- **Career**: Join model with `duration` (DateRange) field tracking tenure at each team
- **Country::START**: Hash constant defining leagues to track (id, season)

## Development Workflows

### Docker Setup (Primary)
```bash
# Start all services (app, postgres, redis, sidekiq)
docker-compose up

# Access Rails console
docker-compose exec app bin/rails console

# Run migrations
docker-compose exec app bin/rails db:migrate

# Trigger data ingestion
docker-compose exec app bin/rails console
> LeagueTeamsWorker.enqueue
```

**Services**:
- Rails app: `http://localhost:3000`
- Sidekiq UI: `http://localhost:3000/sidekiq`
- RailsAdmin: `http://localhost:3000/admin`

### Testing
Uses **Minitest** with **VCR** for API mocking:
- Cassettes: `fixtures/vcr_cassettes/{league,player,team}/`
- Run tests: `bin/rails test`
- **Critical**: Nest VCR cassettes for services making multiple API calls (see `test/services/upsert_player_career_test.rb`)

### Background Jobs
- **Queue System**: Sidekiq (not SolidQueue, despite Rails 8 defaults)
- **Redis Config**: Set via `REDIS_URL_SIDEKIQ` env var
- **Pattern**: Workers call service objects, never contain business logic
- **Testing**: Use `Sidekiq::Testing.inline!` or `.fake!` modes

## Project-Specific Conventions

### Date Handling
Career histories use **open-ended date ranges**:
- `duration`: PostgreSQL DateRange (`start_date..end_date`)
- Active careers: `end_date` is `nil`
- Retired players: `end_date` from last active season + Dec 31

### Upsert Pattern
All external data uses `find_or_create_by!`:
```ruby
Team.find_or_create_by!(external_id: team_id) do |team|
  team.name = team_data[:name]
  # ... set attributes only on creation
end
```

### Admin Interfaces
Two admin systems configured:
- **RailsAdmin**: `/admin` (currently active, see `routes.rb`)
- **ActiveAdmin**: Commented out but dependencies installed

### API-Only Considerations
Despite `config.api_only = false`, the app serves no frontend views. Middleware for sessions/cookies exists solely to support admin UIs.

## Common Tasks

### Add a New League
1. Update `Country::START` in `app/models/country.rb`
2. Add league_id and starting season
3. Run `LeagueTeamsWorker.enqueue`

### Debug Worker Chains
Check Sidekiq UI at `/sidekiq` for:
- Failed jobs (inspect error messages)
- Queue depth (indicates API rate limiting)
- Processed count (monitor progress)

### Inspect Player Journey
```ruby
player = Player.find_by(name: "Player Name")
player.journey # Returns formatted career path string
```

## Key Files Reference
- **Worker chain**: `app/jobs/league_teams_worker.rb` (entry point)
- **API client**: `app/services/football_client.rb`
- **Service base**: `app/services/application_service.rb`
- **League config**: `app/models/country.rb` (START constant)
- **Docker config**: `docker-compose.yml` (4 services setup)
- **Test setup**: `test/test_helper.rb` (VCR configuration)

## Known Patterns to Follow
- Service objects for all external API calls
- Workers only orchestrate, never contain logic
- VCR cassettes for deterministic testing
- DateRange fields for temporal data
- Hard API key in code (TODO: move to credentials)

## API Strategy: Getting Player Career History

### Current Approach
The system uses the **Transfers endpoint** to build complete player career histories:

**Endpoint**: `GET /transfers?player={player_id}`

**Why not `team` parameter?**
- Including `&team={team_id}` limits results to transfers involving only that team
- **Remove team filter** to get complete career history in a single call

### Alternative Endpoints (Not Recommended)
- ❌ `GET /players?id={player_id}&season={year}` - Requires multiple calls per season
- ❌ `GET /players/teams?player={player_id}&season={year}` - Also requires per-season iteration

### Data Processing Pattern
1. Fetch all transfers: `transfers?player={player_id}` 
2. Extract `transfer[:teams][:in]` for each transfer (destination club)
3. Calculate duration using:
   - `start_date`: Current transfer date
   - `end_date`: Next transfer date (or nil for active career)
4. Use `players/seasons?player={player_id}` to determine if player is retired

### API Response Structure
```ruby
{
  response: [{
    player: { id: 154, name: "Player Name" },
    transfers: [
      {
        date: "2015-08-30",
        type: "€ 76M",  # Transfer fee
        teams: {
          in: { id: 50, name: "New Club" },   # Joined club
          out: { id: 85, name: "Old Club" }   # Left club
        }
      }
    ]
  }]
}
```

**Note**: Transfers are ordered chronologically (oldest first), simplifying date range calculation.

# Player Career Journey - API Implementation Plan

## Overview

This document outlines the strategy for fetching a football player's career journey (teams played for) using the [API-Football v3](https://www.api-football.com/documentation-v3) and storing it in the `careers` table.

---

## API Endpoints

### 1. **Players/Teams** (Career Journey)
**Endpoint:** `GET /players/teams?player={player_id}`

Returns the list of teams and seasons in which the player played during his career.

```ruby
# Example Request
GET https://v3.football.api-sports.io/players/teams?player=276

# Example Response
{
  "get": "players/teams",
  "parameters": { "player": "276" },
  "results": 8,
  "response": [
    {
      "team": {
        "id": 1278,
        "name": "Portuguesa Santista",
        "logo": "https://media.api-sports.io/football/teams/1278.png"
      },
      "season": 2009
    },
    {
      "team": {
        "id": 616,
        "name": "Santos",
        "logo": "https://media.api-sports.io/football/teams/616.png"
      },
      "season": 2010
    },
    {
      "team": {
        "id": 85,
        "name": "Paris Saint Germain",
        "logo": "https://media.api-sports.io/football/teams/85.png"
      },
      "season": 2017
    }
    // ... more entries
  ]
}
```

---

### 2. **Transfers** (Transfer History)
**Endpoint:** `GET /transfers?player={player_id}`

Returns all transfer records for a player including dates, teams, and transfer fees.

```ruby
# Example Request
GET https://v3.football.api-sports.io/transfers?player=276

# Example Response
{
  "get": "transfers",
  "parameters": { "player": "276" },
  "results": 1,
  "response": [
    {
      "player": {
        "id": 276,
        "name": "Neymar"
      },
      "update": "2023-07-15T00:00:00+00:00",
      "transfers": [
        {
          "date": "2017-08-03",
          "type": "€ 222M",
          "teams": {
            "in": {
              "id": 85,
              "name": "Paris Saint Germain",
              "logo": "https://media.api-sports.io/football/teams/85.png"
            },
            "out": {
              "id": 529,
              "name": "Barcelona",
              "logo": "https://media.api-sports.io/football/teams/529.png"
            }
          }
        },
        {
          "date": "2013-06-03",
          "type": "€ 88M",
          "teams": {
            "in": {
              "id": 529,
              "name": "Barcelona",
              "logo": "https://media.api-sports.io/football/teams/529.png"
            },
            "out": {
              "id": 616,
              "name": "Santos",
              "logo": "https://media.api-sports.io/football/teams/616.png"
            }
          }
        }
        // ... more transfers
      ]
    }
  ]
}
```

**Transfer Types:**
- `€ XXM` - Paid transfer with fee
- `Free` - Free transfer
- `Loan` - Loan move
- `N/A` - Unknown/Not available

---

## Data Priority Strategy

**Important:** The `/transfers` endpoint provides more detailed information (exact dates, transfer fees) and should be the **primary source** for career data.

| Source | Use Case |
|--------|----------|
| `/transfers` | **Preferred** - All teams in between first and last |
| `/players/teams` | First team (youth/debut) and current/last team only |

### Rationale:
- Transfers include exact dates and fees
- `/players/teams` may show teams where player never had an official transfer (youth academy, current team)
- First team often has no "transfer in" record (player started there)
- Last/current team may not have a transfer record yet

---

## Implementation Strategy

### Step 1: Fetch Career Data

```ruby
# Call both endpoints
career_data = FootballClient.new.get("/players/teams", player: player_api_id)
transfers_data = FootballClient.new.get("/transfers", player: player_api_id)
```

### Step 2: Process Data (Transfers Preferred)

```ruby
transfers = extract_transfers(transfers_data)
career_teams = career_data["response"]

# Sort career teams by season to identify first and last
sorted_teams = career_teams.sort_by { |t| t["season"] }
first_team_id = sorted_teams.first&.dig("team", "id")
last_team_id = sorted_teams.last&.dig("team", "id")

# Sort transfers by date to calculate durations
sorted_transfers = transfers.sort_by { |t| t["date"] }

# Build career records from TRANSFERS first (preferred source)
sorted_transfers.each_with_index do |transfer, index|
  team_in = transfer.dig("teams", "in")
  start_date = Date.parse(transfer["date"])
  
  # End date is either next transfer date or nil (still at club)
  next_transfer = sorted_transfers[index + 1]
  end_date = next_transfer ? Date.parse(next_transfer["date"]) : nil
  
  Career.find_or_create_by(
    player: player,
    football_team: FootballTeam.find_by(api_id: team_in["id"])
  ) do |career|
    career.duration = start_date..end_date
  end
end

# Add FIRST team from /players/teams (may not have transfer record - youth/academy)
first_entry = sorted_teams.first
if first_entry && !Career.exists?(player: player, football_team_id: first_team_id)
  # End date is the first transfer date (when player left)
  first_transfer_date = sorted_transfers.first ? Date.parse(sorted_transfers.first["date"]) : nil
  
  Career.create!(
    player: player,
    football_team: FootballTeam.find_by(api_id: first_team_id),
    duration: Date.new(first_entry["season"], 7, 1)..first_transfer_date
  )
end

# Add LAST/CURRENT team from /players/teams (may not have transfer record yet)
last_entry = sorted_teams.last
if last_entry && !Career.exists?(player: player, football_team_id: last_team_id)
  # Start from last transfer, no end date (still at club)
  last_transfer_date = sorted_transfers.last ? Date.parse(sorted_transfers.last["date"]) : Date.new(last_entry["season"], 7, 1)
  
  Career.create!(
    player: player,
    football_team: FootballTeam.find_by(api_id: last_team_id),
    duration: last_transfer_date..nil
  )
end
```

---

## Career Table Schema

The existing `careers` table:

| Column | Type | Description |
|--------|------|-------------|
| `player_id` | integer | Foreign key to players table |
| `football_team_id` | integer | Foreign key to football_teams table |
| `duration` | daterange | Date range (start_date, end_date) at this team |

**Note:** The `duration` is a PostgreSQL `daterange` type that stores the period the player was at the team.

---

## Service Implementation

```ruby
# app/services/upsert_player_career.rb
class UpsertPlayerCareer < ApplicationService
  def initialize(player)
    @player = player
    @client = FootballClient.new
  end

  def call
    career_response = @client.get("/players/teams", player: @player.api_id)
    transfers_response = @client.get("/transfers", player: @player.api_id)
    
    transfers = extract_transfers(transfers_response)
    career_teams = career_response["response"] || []
    
    return if career_teams.blank? && transfers.blank?
    
    # Sort to identify first and last team
    sorted_teams = career_teams.sort_by { |t| t["season"] }
    first_team_api_id = sorted_teams.first&.dig("team", "id")
    last_team_api_id = sorted_teams.last&.dig("team", "id")
    
    # Sort transfers by date to calculate durations
    sorted_transfers = transfers.sort_by { |t| t["date"] }
    
    # STEP 1: Process TRANSFERS first (preferred source for middle career)
    sorted_transfers.each_with_index do |transfer, index|
      team_in = transfer.dig("teams", "in")
      team = FootballTeam.find_by(api_id: team_in["id"])
      next unless team
      
      start_date = Date.parse(transfer["date"])
      next_transfer = sorted_transfers[index + 1]
      end_date = next_transfer ? Date.parse(next_transfer["date"]) : nil
      
      Career.find_or_create_by!(
        player: @player,
        football_team: team
      ) do |career|
        career.duration = start_date..end_date
      end
    end
    
    # STEP 2: Add FIRST team if not already added (youth/academy - no transfer in)
    if first_team_api_id
      first_team = FootballTeam.find_by(api_id: first_team_api_id)
      if first_team && !Career.exists?(player: @player, football_team: first_team)
        first_transfer_date = sorted_transfers.first ? Date.parse(sorted_transfers.first["date"]) : nil
        
        Career.create!(
          player: @player,
          football_team: first_team,
          duration: Date.new(sorted_teams.first["season"], 7, 1)..first_transfer_date
        )
      end
    end
    
    # STEP 3: Add LAST/CURRENT team if not already added (no transfer record yet)
    if last_team_api_id && last_team_api_id != first_team_api_id
      last_team = FootballTeam.find_by(api_id: last_team_api_id)
      if last_team && !Career.exists?(player: @player, football_team: last_team)
        last_transfer_date = sorted_transfers.last ? Date.parse(sorted_transfers.last["date"]) : Date.new(sorted_teams.last["season"], 7, 1)
        
        Career.create!(
          player: @player,
          football_team: last_team,
          duration: last_transfer_date..nil
        )
      end
    end
  end
  
  private
  
  def extract_transfers(response)
    return [] if response["response"].blank?
    response["response"].first&.dig("transfers") || []
  end
end
```

---

## Background Job

```ruby
# app/jobs/fetch_player_career_job.rb
class FetchPlayerCareerJob < ApplicationJob
  queue_as :default

  def perform(player_id)
    player = Player.find(player_id)
    UpsertPlayerCareer.call(player)
  end
end
```

---

## API Rate Limiting

| Plan | Requests/Day | Requests/Minute |
|------|-------------|-----------------|
| Free | 100 | 10 |
| Basic | 7,500 | 30 |

**Recommendation:** Cache career data as it doesn't change frequently. Call once per player when needed.

---

## API Call Summary

| Purpose | Endpoint | Required Params |
|---------|----------|-----------------|
| Career Teams | `/players/teams` | `player` (API ID) |
| Transfers | `/transfers` | `player` (API ID) |

---

## Notes

- Player IDs are unique across the API
- Team logos URL: `https://media.api-sports.io/football/teams/{team_id}.png`
- API uses GET requests with `x-apisports-key` header
- Update frequency: Several times a week
- Recommended calls: 1 call per week per player

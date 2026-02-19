# Player Career Data Plan

## Diogo Dalot Career Analysis (External ID: 886)

### Expected Senior Career (from Wikipedia)

| Team | Years | Apps |
|------|-------|------|
| Porto B | 2016–2018 | 23 |
| Porto | 2017–2018 | 6 |
| Manchester United | 2018– | 163+ |
| AC Milan (loan) | 2020–2021 | 21 |

**Key Career Timeline:**
1. **2016-2017**: Porto B (LigaPro debut January 2017)
2. **2017-2018**: Porto B + Porto First Team
3. **June 2018**: Transfer to Manchester United (£19m)
4. **October 2020 - June 2021**: Loan to AC Milan
5. **2021 onwards**: Back at Manchester United (current)

---

## API Endpoints Available

### 1. `/transfers?player={id}`
**What it provides:**
- List of transfer movements between clubs
- Transfer date, type (Loan, Permanent, Free, etc.)
- Source and destination teams with IDs
- Transfer fee (if available)

**Limitations:**
- Does NOT include youth academy → senior team progression
- Does NOT include B-team appearances
- May miss loan returns (only shows initial loan)

### 2. `/players/teams?player={id}` ⭐ NEW (v3.9.3)
**What it provides:**
- Complete list of teams player has been associated with
- `seasons` array showing which seasons player was at each team
- Team ID and name

**Example Response Structure:**
```json
{
  "team": { "id": 212, "name": "FC Porto" },
  "seasons": [2016, 2017]
}
```

**Advantages:**
- Shows academy/youth teams
- Shows complete season coverage
- Can derive first team from earliest season
- Can derive current team from latest season

### 3. `/players/seasons?player={id}`
**What it provides:**
- List of all seasons where player has statistics
- Used to determine if player is still active

### 4. `/players?id={id}&season={year}`
**What it provides:**
- Detailed player statistics per season
- League and team association for that season
- Useful for verifying team associations

### 5. `/players/squads?player={id}`
**What it provides:**
- Current squad associations
- Alternative source for current team

---

## Current Implementation Analysis

### `app/services/upsert_player_career.rb`

#### Current Flow:
1. Fetch transfers via `/transfers?player={id}`
2. Fetch career teams via `/players/teams?player={id}`
3. Extract first and last team from career_teams
4. Add first team (youth/academy) if not in transfers
5. Add last team (current) if not in transfers  
6. Process transfer movements
7. Merge consecutive careers at same club

#### ✅ What Works Well:
- Uses both `/transfers` and `/players/teams` endpoints
- Handles `seasons` as array (fixed from initial bug)
- Merges consecutive careers to avoid duplicates
- Handles loan returns correctly
- Creates teams and countries on-the-fly

#### ❌ Current Issues/Limitations:

##### 1. **B-Team vs First Team Not Distinguished**
The API doesn't clearly distinguish Porto B from Porto First Team. Wikipedia shows:
- Porto B: 2016–2018 (23 apps)
- Porto: 2017–2018 (6 apps)

Current implementation would likely create only ONE Porto career (they have different team IDs in the API).

##### 2. **Season Array Handling Could Be Smarter**
Currently uses `seasons.min` for start year, but could:
- Create separate career entries for non-consecutive seasons
- Better handle loan spells (same team, different season blocks)

##### 3. **Overlap Detection is Aggressive**
Line 62-64: `overlaps_with_any = @player.careers.any? { |c| careers_overlap?(c.duration, new_duration) }`

This prevents any overlapping careers, but **legitimate overlaps exist**:
- Player at Porto B AND Porto First Team simultaneously (2017-2018)

##### 4. **No Appearance Data**
The Career model only tracks duration, not how many appearances the player made. This misses:
- Significance of each spell (23 apps at Porto B vs 6 apps at Porto)
- Validation of career data (0 apps = probably not really there)
- Quiz-valuable data ("How many apps did X make for Y?")

---

## Proposed Improvements

### Improvement 1: Better Season Gap Detection

For players with loans or interrupted spells at a club, seasons may not be consecutive:

```ruby
def process_career_teams(career_teams)
  career_teams.each do |team_data|
    seasons = team_data[:seasons]
    season_groups = group_consecutive_seasons(seasons)
    
    season_groups.each do |group|
      create_career_for_season_group(team_data, group)
    end
  end
end

def group_consecutive_seasons(seasons)
  # [2016, 2017, 2020, 2021] → [[2016, 2017], [2020, 2021]]
  seasons.sort.chunk_while { |a, b| b - a == 1 }.to_a
end
```

This would create:
- Manchester United career 1: 2018-2020 (before loan)
- AC Milan career: 2020-2021 (loan)
- Manchester United career 2: 2021-present (after loan)

### Improvement 2: Use `/players?id={id}&season={year}` for Verification

For complex careers, verify team associations:

```ruby
def verify_team_for_season(player_id, team_id, season)
  stats = FootballClient.call(end_point: "players?id=#{player_id}&season=#{season}")
  return false if stats.blank?
  
  stats[0][:statistics].any? { |s| s.dig(:team, :id) == team_id }
end
```

### Improvement 3: Relax Overlap Detection for Different Teams

Currently, overlap detection prevents ANY overlapping careers. This should only prevent overlaps for the SAME team:

```ruby
def can_create_career?(team_id, new_duration)
  # Only check for overlap with careers at the SAME team
  @player.careers
    .where(football_team_id: team_id)
    .none? { |c| careers_overlap?(c.duration, new_duration) }
end
```

This allows:
- Porto B career (2016-2018) to overlap with Porto career (2017-2018)
- They are different teams in the API

### Improvement 4: Add Appearances to Career

Add an `appearances` column to track how many times the player played for each team:

```ruby
# Migration
add_column :careers, :appearances, :integer, default: 0
```

**Data source:** `/players?id={id}&season={year}` returns statistics including appearances per team.

```ruby
def fetch_appearances_for_career(player_id, team_id, seasons)
  total_appearances = 0
  
  seasons.each do |season|
    stats = FootballClient.call(end_point: "players?id=#{player_id}&season=#{season}")
    next if stats.blank? || stats[0].nil?
    
    team_stats = stats[0][:statistics]&.find { |s| s.dig(:team, :id) == team_id }
    next unless team_stats
    
    total_appearances += team_stats.dig(:games, :appearences) || 0
  end
  
  total_appearances
end
```

**Trade-off:** This requires 1 API call per season, so a player with 10 seasons = 10 extra calls. Consider:
- Only fetch appearances for "significant" careers (duration > 1 year)
- Batch fetch and cache results
- Run as a separate background job after career creation

---

## API Call Strategy

### Optimal Call Sequence:

```ruby
def call
  # 1. Get career timeline overview (low API cost)
  career_teams = fetch_player_teams  # /players/teams
  
  # 2. Get transfer movements (low API cost)
  transfers = fetch_player_transfers  # /transfers
  
  # 3. Get active seasons (low API cost)
  active_seasons = fetch_active_seasons  # /players/seasons
  
  # 4. For each unique team, fetch team details (cached)
  unique_team_ids = extract_unique_team_ids(career_teams, transfers)
  teams = unique_team_ids.map { |id| find_or_create_team(id) }
  
  # 5. Create career records with duration
  careers = create_careers_from_data(career_teams, transfers, teams)
  
  # 6. Fetch appearances for each career (can be async/background job)
  careers.each do |career|
    team_data = career_teams.find { |ct| ct.dig(:team, :id) == career.football_team.external_id }
    seasons = team_data[:seasons] || []
    appearances = fetch_appearances_for_seasons(seasons, career.football_team.external_id)
    career.update!(appearances: appearances)
  end
end

def fetch_appearances_for_seasons(seasons, team_external_id)
  total = 0
  seasons.each do |season|
    stats = FootballClient.call(end_point: "players?id=#{@player.external_id}&season=#{season}")
    next if stats.blank? || stats[0].nil?
    
    team_stats = stats[0][:statistics]&.find { |s| s.dig(:team, :id) == team_external_id }
    total += team_stats.dig(:games, :appearences) || 0 if team_stats
  end
  total
end
```

### API Cost Estimation (per player):

| Endpoint | Calls | Notes |
|----------|-------|-------|
| `/transfers` | 1 | Always |
| `/players/teams` | 1 | Always |
| `/players/seasons` | 1 | Always |
| `/teams?id={id}` | N | Per unique team (cached) |
| `/players?id={id}&season={year}` | S | Per season for appearances |

**Typical player (5 seasons)**: 8-10 API calls
**Complex career (like Dalot with 10 seasons)**: 13-18 API calls

### Optimization: Background Job for Appearances

To reduce initial API load, appearances can be fetched separately:

```ruby
# In UpsertPlayerCareer - just create careers
def call
  # Steps 1-5 only (no appearances)
  create_careers_without_appearances
end

# Separate job to populate appearances
class FetchCareerAppearancesJob < ApplicationJob
  def perform(player_id)
    player = Player.find(player_id)
    player.careers.each do |career|
      appearances = fetch_appearances(player, career)
      career.update!(appearances: appearances)
    end
  end
end
```

---

## Diogo Dalot Expected Output

With the current implementation, player 886 should have:

| Team | Duration | Apps | Notes |
|------|----------|------|-------|
| FC Porto | 2017-07-01 to 2018-06-06 | 6 | First team from /players/teams |
| Manchester United | 2018-06-06 to 2020-10-04 | 35 | From transfer |
| AC Milan | 2020-10-04 to 2021-07-01 | 33 | Loan spell |
| Manchester United | 2021-07-01 to present | 200+ | After loan return |

---

## Implementation Priority

1. **P0 - Critical**: Better consecutive season handling (split non-consecutive seasons)
2. **P1 - High**: Relax overlap detection to only check same team
3. **P1 - High**: Add appearances column and fetch from `/players?id={id}&season={year}`
4. **P2 - Medium**: Add verification using `/players?id={id}&season={year}`

---

## Testing Strategy

```ruby
# Test cases for player 886 (Diogo Dalot)
test "creates career for Porto" do
  # First season should be 2017 or 2018
end

test "handles loan to AC Milan" do
  # Should create Milan career Oct 2020 - June/July 2021
end

test "handles loan return to Manchester United" do
  # Should continue Man United career from July 2021
end

test "current team has no end date" do
  # Manchester United career.duration.end should be nil
end

test "does not create duplicate careers for same team" do
  # Idempotent: calling twice creates same records
end
```

---

## Summary

The current implementation is **functional** for most careers. The main improvements needed are:

1. **Season gap handling** - Split non-consecutive seasons into separate career entries
2. **Overlap detection refinement** - Only prevent overlaps for the same team, not different teams
3. **Appearances tracking** - Add appearances count from `/players?id={id}&season={year}` for quiz value and data validation
4. **Optional verification** - Use detailed stats endpoint for complex career validation

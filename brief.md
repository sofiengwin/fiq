# Brief — Data-collection pipeline Phase 1 (PL 39 earliest-back)

Source of truth: `doc/data-collection.md`, `doc/quiz.md`, `doc/backend.md`, `doc/README.MD` (frozen). This brief adds no new features beyond those docs.

## What we are building

A completeness-first, probe-gated backfill + stale-only nightly refresh for Premier League (league 39) back to the earliest retrievable season, with a coverage gate that proves zero missing data in the retrieved window.

Phase 1 pipeline in one flow:

1. **P1 probe (≤10 requests)** finds the earliest PL season with data. Result is an allowlist of seasons + a dead-season list. Backfill may only pull allowlisted seasons, never past present.
2. **Capped backfill** pulls base data per allowlisted season via paginated `players?team&season` union (~40 reqs/season), cache-first in `data/raw/`, 0.6s throttle, caps 500 (backfill) / 200 (nightly), resume-safe rerun ~0 requests.
3. **Stats prereq** populates quiz-required fields: players `dob/nationality/photo_url`; careers `goals` (mandatory), `assists/cards` (nullable), `competition_id` FK. No `minutes_played`.
4. **Coverage gate** proves per-season completeness: zero teams without players, zero players without careers in the retrieved window; dead/partial seasons listed not silently missing; senior players with total apps >= 1 excluded from quiz but kept in DB/cache with names reported.
5. **Nightly stale-only refresh** (02:00 UTC, Solid Queue recurring, queue `team_sync`, cap 200) re-syncs only rows whose planned `last_refreshed_at` is nil or > 30 days old.

## Who it is for

- Quiz generation (LLM + rule-based fallback) needs reliable player/team/career/competition/country data with dob/nationality/photo and goals/assists/cards.
- Operators need a per-season coverage report and a dead-season list instead of silent gaps.
- The app needs data that heals itself (stale-only nightly) without unbounded API spend.

## Must do (in scope)

- PL 39 earliest-back via P1 probe ≤10 reqs; cache probe + all raw payloads under `data/raw/`; dead-season list artifact.
- Base fetch = `players?team&season` paginated union, ~40/season; throttle 0.6s; cache-first resume; job cap allowlist, no recursion past present, stop on budget (500 backfill / 200 nightly).
- Stats prereq migrations + wiring (players dob/nationality/photo_url; careers goals/assists/cards + competition_id; `last_refreshed_at` on teams/players/careers; nil = stale).
- Coverage gate per season: zero missing in retrieved window, dead/partial reported, senior >= 1-apps reported-but-kept.
- Nightly 02:00 UTC stale-only job + `recurring.yml` entry.
- Dev path stays `docker compose`; host DB on 54321 via DATABASE_URL override.

## Must NOT do (out of scope)

- No La Liga / Ligue 1 / Bundesliga / Serie A expansion (deferred, per doc).
- No `minutes_played` anywhere.
- No errata pipeline work — frontend-only flag, no re-fetch queue (explicitly deferred).
- No pre-quiz staleness gate (deferred per doc).
- No `review_queue` table/model (removed by governance decision).
- No unbounded `LeagueTeamsJob` season+1 recursion — replaced by allowlist + caps.
- No live bulk-pull of dead seasons found by the probe.

## Existing state (verified, constrains the plan)

- `FootballClient` uses a 450/min Limiter, no 0.6s spacing, no `data/raw/` cache. Endpoints in use: `teams?league&season`, `players/squads?team` (current squad only, not per-season), `players/profiles`, `transfers`, `players/teams`, `players/seasons`, `teams?id`. No `players?team&season` union yet.
- `UpsertLeagueTeams` works for one league+season; no caching, no allowlist, no `last_refreshed_at`.
- `UpsertTeamPlayers` uses squads + per-player profiles (expensive) and creates stub careers; no dob/nationality/photo, no stats, no cache.
- `UpsertPlayerCareer` builds duration ranges from transfers + gap-split; no goals/assists/cards, no competition_id, no `last_refreshed_at`. Has reserve-team name filter but not the apps>=1 senior report rule.
- `LeagueTeamsJob` recurses `season+1` with only a `Time.zone.now.year < season` guard — unbounded, no allowlist, no caps. Must be fixed, not extended.
- Schema has none of the planned fields (no dob/nationality/photo_url, no goals/assists/cards/competition_id, no `last_refreshed_at`).
- `data_coverage.rake` is a global-counts draft only (no per-season, no gate exit code, no dead/partial or senior-apps reporting).
- `data/raw/` contains only `.keep`; `recurring.yml` has no `data_refresh` entry.

## How we know it works (acceptance)

- `bin/rails db:migrate` adds exactly the planned fields; `minutes_played` absent; rollback clean.
- Probe runs twice: first ≤10 API requests and writes `data/raw/probe_39*.json` + allowlist + dead list; second run ~0 requests (cache-hit).
- Backfill of one probe-allowlisted season end-to-end makes ≤ ~40 base requests; rerun ~0; coverage rake for that season reports zero missing (or lists dead/partial explicitly) and exits 0; exit non-zero when truly missing.
- Nightly job dry-run enqueues only nil-or->30d rows and respects cap 200; `recurring.yml` schedules it daily 02:00 UTC on queue `team_sync`.
- Seeded quiz-relevant player shows dob/nationality/photo_url and career goals/assists/cards + competition_id.

## Assumptions (no guessing on plan-changing items)

- API-Sports `v3.football.api-sports.io` stays the source; `FootballClient` keeps its credential + error shape, we only add cache + spacing around it.
- "Senior >= 1" means total career `appearances` >= 1 summed per player; these rows stay in DB/cache, are excluded from quiz candidacy, names reported by the coverage task.
- `players?team&season` pagination follows the existing api-sports `paging` envelope; union key is player id per team+season.
- Present-season bound = current calendar year (`Time.zone.now.year`); no future-season enqueue.
- Stale = `last_refreshed_at.nil? || last_refreshed_at <= 30.days.ago`.

## Open risks

- Earliest retrievable PL season unknown until probe runs — allowlist length (and total ~40/season cost) cannot be quoted in advance.
- Current `players/squads` + `players/profiles` path is far more expensive than the planned `players?team&season` union; backfill must switch, not optimize, the old path.
- `ApplicationJob#wait_time` staggers via last scheduled execution +30s; combined with 0.6s throttle and caps, throughput planning needs a measured trial season before full earliest-back run.

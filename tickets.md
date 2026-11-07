# Tickets — Data-collection pipeline Phase 1 (PL 39 earliest-back)

Source: frozen `doc/data-collection.md` + `doc/quiz.md` + `doc/backend.md` + `doc/README.MD`. Scope notes in `brief.md`. No implementation code in this file — builders build.

Conventions for every ticket below: small enough for one builder session, independently testable, ordered so earlier tickets unblock later ones. Run dev via `docker compose` with host DB on 54321 (`DATABASE_URL` override). Never add `minutes_played`, errata pipeline, `review_queue`, or leagues beyond PL 39.

---

## T1 — Migrations: stats prereq + last_refreshed_at

- **Title:** Add stats-prereq columns and staleness timestamps, no minutes
- **Why:** Quiz needs dob/nationality/photo and goals/assists/cards + competition link, and nightly refresh needs a staleness marker — none exist in schema today.
- **Exactly what to do:**
  - New migration(s): `players` += `dob:date`, `nationality:string`, `photo_url:string`, `last_refreshed_at:datetime`; `football_teams` += `last_refreshed_at:datetime`; `careers` += `goals:integer (default 0, not-null after backfill)`, `assists:integer (nullable)`, `cards_yellow:integer (nullable)`, `cards_red:integer (nullable)`, `competition_id:bigint (nullable FK → competitions)`, `last_refreshed_at:datetime`.
  - Add FK `careers.competition_id → competitions.id`, index on each `last_refreshed_at` and on `careers.competition_id`.
  - Keep `goals` nullable-or-default on migrate so existing rows survive; enforce presence at the model/upsert layer in T6, not via DB not-null on day one.
  - Update `db/schema.rb` via normal migrate; touch no other tables.
- **Done when:** `bin/rails db:migrate` succeeds from clean, `bin/rails db:migrate:redo` round-trips, `db/schema.rb` shows exactly the columns above, and `grep -r minutes_played db/ app/models` returns nothing.
- **Out of scope:** Populating the new columns (T6); stale query scopes (T7); any quiz/errata tables.
- **Depends on:** none.

## T2 — FootballClient: cache-first data/raw/ + 0.6s throttle

- **Title:** Wrap FootballClient reads with file cache and request spacing
- **Why:** Probe (T3) and backfill (T5) both require cache-first resume (~0 reqs on rerun) and 0.6s throttle; today the client has only a 450/min limiter and hits the API every call.
- **Exactly what to do:**
  - Add a read-through cache: every GET endpoint+params maps to one deterministic JSON file under `data/raw/` (e.g. endpoint slug + sorted query hash); on hit, return parsed file with zero HTTP; on miss, wait per throttle, call API, then write file atomically.
  - Enforce minimum 0.6s spacing between live API calls in the same process (in addition to, not replacing, the existing Limiter/rate-limit error handling); keep credential headers and `errors.rateLimit` behavior unchanged.
  - Add opt-out (env flag or explicit param) used only by tests; default in dev/prod is cache-on. Never delete `.keep`; never cache writes (there are none).
- **Done when:** With a cleared `data/raw/` subset, first call for `teams?league=39&season=<S>` hits the network once and writes a file; second identical call makes zero HTTP (verifiable via request stub/log count) and returns equal data; back-to-back live calls are spaced ≥0.6s apart in logs.
- **Out of scope:** Probe logic (T3); changing upserters or jobs; nightly schedule (T7).
- **Depends on:** none (parallelizable with T1).

## T3 — P1 probe: earliest-back PL seasons, ≤10 reqs, dead-season list

- **Title:** Probe PL 39 for earliest retrievable season and emit allowlist + dead list
- **Why:** Backfill must only pull seasons that actually have data and must never bulk-pull dead seasons; the probe gates everything.
- **Exactly what to do:**
  - New rake task `data:probe_pl39` (or equivalent single entry point): starting from the present season and stepping back, use `teams?league=39&season=<S>` (via T2 cached client) to find the earliest season with a non-empty teams payload, stopping after at most 10 live requests total.
  - Write artifacts under `data/raw/`: `probe_39.json` (per-season tried → team count + cache file ref), `seasons_allowlist_39.json` (retrievable seasons only, capped at present year), `dead_seasons_39.json` (empty/error seasons, never to be bulk-pulled).
  - Rerun must be cache-first: second invocation makes ~0 live requests and reproduces identical artifacts. Log live-request count each run.
- **Done when:** First run makes ≤10 live requests and writes all three artifacts; deleting artifacts and rerunning with warm cache makes ~0 live requests; `dead_seasons_39.json` lists at least the shape `{season, reason}` per dead season; no season > current year appears in the allowlist.
- **Out of scope:** Pulling players/careers (T5); coverage math (T4); touching `LeagueTeamsJob`.
- **Depends on:** T2 (cache + throttle). Needs T1 only for awareness, not blocked by it.

## T4 — Coverage gate per season (upgrade data_coverage.rake)

- **Title:** Per-season PL 39 coverage report with zero-missing gate
- **Why:** The draft rake only prints global counts; Phase 1 acceptance requires per-season proof of zero missing plus explicit dead/partial and senior-apps reporting.
- **Exactly what to do:**
  - Rewrite/extend `lib/tasks/data_coverage.rake` to `data:coverage[league_id,season]` (default `39,<season>`) that prints per-season: team count, teams-without-players count + names/ids, players-in-scope count, players-without-careers count + names/ids, dead/partial flags (cross-read `dead_seasons_39.json` when present), and senior list (total appearances >= 1 per player: kept in DB, excluded from quiz, names reported).
  - Gate semantics: exit 0 when teams-without-players == 0 AND players-without-careers == 0 within the retrieved window (dead seasons listed, not counted as missing); exit non-zero otherwise. Never auto-fetch or auto-heal inside the task.
- **Done when:** Against a seeded season with one team missing players and one player missing careers, the task lists both by name and exits non-zero; after fixing fixtures (or pointing at a fully backfilled trial season from T5), it prints per-season lines including dead/partial + senior-apps sections and exits 0.
- **Out of scope:** Backfill itself (T5); probe (T3); nightly (T7).
- **Depends on:** T1 (needs `appearances`/new stat columns present to define senior + career checks).

## T5 — Capped backfill batch: base union ~40/season, allowlist-only, no recurse past present

- **Title:** Backfill one allowlisted PL season via players?team&season union under cap 500
- **Why:** Today's path (squads + per-player profiles, unbounded season+1 recursion) cannot do earliest-back safely or cheaply; the doc mandates the paginated per-season union with caps and allowlist.
- **Exactly what to do:**
  - New bounded batch entry point (rake `data:backfill_pl39[season]` calling a service/job, not `LeagueTeamsJob.start_ingestion`): reads `seasons_allowlist_39.json`, refuses seasons not on the allowlist or > present year, then for that season does `teams?league=39&season` → paginated `players?team=<id>&season=<S>` union (~40 reqs/season) → upsert teams/players/careers skeletons with `competition_id` set and `last_refreshed_at = now` on touched rows.
  - Enforce: cache-first (T2) so rerun ~0 live reqs; hard stop at 500 live reqs per invocation (log + clean exit, resume-safe); no enqueue of seasons past present; remove-or-neutralize the unbounded `LeagueTeamsJob season+1` self-recursion for this path (leave existing job classes intact for later tickets, just don't use recursion here).
  - Detailed career stats fill stays in T6; this ticket only guarantees base skeleton + linkage so T4 can measure completeness.
- **Done when:** Backfilling a single allowlisted season end-to-end makes ≤ ~40 live base requests (plus cache writes visible under `data/raw/`); immediate rerun makes ~0 live requests; `data:coverage[39,<season>]` (T4) exits 0 or lists only declared dead/partial; invoking with a dead or future season refuses without any live player-fetch requests; 500-cap trip is exercised via a stubbed/low-cap run and exits cleanly resumable.
- **Out of scope:** Stats detail fill (T6); probe (T3); nightly (T7); multi-season earliest-to-present full run (operator runs T5 per allowlisted season after this lands).
- **Depends on:** T1, T2, T3, T4.

## T6 — Stats wiring: populate dob/nationality/photo + goals/assists/cards + competition_id

- **Title:** Fill quiz-required player/career stat fields during upsert, no minutes
- **Why:** T5 builds the skeleton; quiz generation is still blocked until dob/nationality/photo and per-career goals/assists/cards + competition link are actually stored.
- **Exactly what to do:**
  - Extend the upsert paths used by T5 (`UpsertTeamPlayers` and `UpsertPlayerCareer` or their successors): set `players.dob/nationality/photo_url` from the profile payload and `careers.goals (mandatory)/assists/cards_yellow/cards_red (nullable)/competition_id` from the statistics payload, updating `last_refreshed_at` on every touched row.
  - Validate: player without dob/nationality/photo still saves (nullable) but is flagged in logs; career without goals is rejected/logged (goals mandatory); never read, write, or migrate `minutes_played`.
  - Keep existing duration/gap-split and reserve-team behavior unchanged.
- **Done when:** Re-running the T5 trial season populates a spot-checked quiz-relevant player (dob + nationality + photo_url present) and at least one career row per spot-checked player with goals present, assists/cards nullable-allowed, and `competition_id` pointing at the PL competition; `minutes_played` appears nowhere in code or schema.
- **Out of scope:** Coverage changes (T4); nightly (T7); precision transfers/teams/seasons expansion beyond what exists.
- **Depends on:** T1, T5.

## T7 — Nightly stale-only refresh, 02:00 UTC, cap 200

- **Title:** Schedule and implement stale-only nightly sync on team_sync
- **Why:** Data must heal itself without re-pulling everything; the doc requires nightly stale-only via last_refreshed_at with a 200 cap, which does not exist today.
- **Exactly what to do:**
  - Add `data_refresh` entry to `config/recurring.yml`: daily `at 2am UTC` (Solid Queue recurring syntax), queue `team_sync`, capped job that selects only rows with `last_refreshed_at IS NULL OR last_refreshed_at <= 30.days.ago` across teams/players/careers (PL 39 scope first), re-syncs via the cached client (T2), updates `last_refreshed_at`, and stops cleanly at 200 live requests per run (resume next night).
  - Provide a dry-run mode (rake or job arg) that prints would-refresh counts per table without enqueueing or calling the API. Pre-quiz gate stays deferred — do not block quiz paths on staleness.
- **Done when:** `recurring.yml` contains the 02:00 UTC `team_sync` entry; dry-run on a DB with 3 stale + 2 fresh rows reports exactly the 3 stale and enqueues/calls nothing; live run with stubbed client refreshes only stale rows, updates their `last_refreshed_at`, respects the 200 cap, and leaves fresh rows untouched.
- **Out of scope:** Errata (frontend-only, no re-fetch queue); pre-quiz staleness blocking; multi-league expansion.
- **Depends on:** T1, T2.

---

### Build order

1. T1 + T2 in parallel (migrations; client cache/throttle).
2. T3 probe (needs T2).
3. T4 coverage gate (needs T1; uses T3 artifacts when present).
4. T5 capped backfill trial season (needs T1–T4).
5. T6 stats wiring (needs T1, T5).
6. T7 nightly stale-only (needs T1, T2; best verified after T5+T6 so stale/fresh rows exist).

### Human decisions still needed before full earliest-back run

- Confirm present-season bound as calendar year vs league-season label (e.g. 2025 vs 2025/26) before T5 runs past one trial season.
- Confirm `probe_39.json` / allowlist / dead-list filenames and whether they are committed or gitignored after T3 lands.
- Confirm whether T5's trial season should be present season or a small historical season to calibrate the ~40/season budget.

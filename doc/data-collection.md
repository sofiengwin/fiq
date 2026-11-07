# Data collection — live-only fan-out (from 74509a2 baseline, no response cache)
- Priority: completeness before staleness. Phase 1 = PL (39) back to earliest retrievable via probe: all teams → squads → careers + competitions/countries.
- Coverage gate: zero teams without players, zero players without careers in retrieved window (dead listed, not missing); senior filter total apps >=1 excluded from quiz with names reported, kept in DB; per-season entries + dead/partial reported.
- Stale threshold: 30 days via last_refreshed_at on teams/players/careers (nil = stale).
- Refresh: nightly stale-only `FootballClient` sync via last_refreshed_at, Solid Queue recurring daily 02:00 UTC queue team_sync cap 200 (pre-quiz gate removed).
- Errata: out of pipeline Phase 1. Frontend-only flag (no re-fetch queue yet).

## Plan (live-only)
1. Completeness PL 39 earliest-back: P1 probe confirmed 2010-2026 retrievable, dead 2007-2009. Backfill to present per season. Accept: coverage zero missing in retrieved window, dead seasons listed.
2. Staleness 30-day: last_refreshed_at + stale?, nightly stale-only job. Accept: stale auto-refreshes. Pre-quiz gate removed.
3. Errata (deferred, frontend-only): flag stored for review; no pipeline re-fetch in Phase 1.
4. Expand: La Liga 140, Ligue 1 61, Bundesliga 78, Serie A 135. Accept: coverage per league.

## Approach: live-only fan-out (keep 74509a2 chain shape, no cache)
- Dev: docker compose for development work; db on host 54321 (DATABASE_URL override for host rails).
- Base: live `LeagueTeamsJob` chain (teams?league → squads?team + profiles → transfers/teams/seasons + appearances), bounded: allowlist seasons from probe only, no recurse past present, per-run caps, 0.6s throttle + existing limiter. Every run hits API; idempotent upserts make reruns safe but full-cost (~40-70 live/season).
- Probe: ≤10 live reqs per league; persists allowlist + dead list to `config/allowlist_<id>.yml` (not `data/raw/`); backfill refuses off-allowlist.
- Stats: players dob/nationality/photo_url; careers goals mandatory, assists/cards nullable, competition_id fk, appearances wired. No minutes_played.
- Precision: transfer-date durations + normalized teams/competitions/countries via existing UpsertPlayerCareer path.
- Governance: probe gates backfill; per-season coverage report; errata frontend-only.
- Budget: ~40-70 live reqs/season; caps 500 backfill / 200 nightly / 5000 auto per day; throttle 0.6s; priority batch > nightly > auto.
- Auto-discovery (dev/test): ON for leagues [39,135,140,61,78], OFF rest (pending-manual, never fetched). Country alias via `config/country_aliases.yml` (seeded canonicals; unmatched create + `alias_missing` warn + fork report).
- First-seen: team missing external_id → skeleton + enqueue squad iff league in scope else pending-manual; player missing id in squad → create + enqueue career; country normalize-only; league → record + probe only, never auto-backfill.
- Discovery state: skipped table for now (logs + coverage run output only); revisit if auto volume/retries grow.
- Refusals: ambiguous/no-match → dead with reason + 30d TTL re-check; name-only never auto-creates (needs id source or curator alias); out-of-scope stays pending-manual.
- Acceptance: career-path bare team gains squad in 1 nightly cycle; alias forks zero; over-budget stays pending zero-HTTP; dead listed with reason, coverage PASS.
- Autodiscovery v1 non-scope: quiz/LLM hooks, review UI (logs only), name-only auto-create.

## Dead code removal (required by live-only change)
- `app/services/football_client.rb`: remove file-cache layer (`cache_path_for`, `cache_dir`, tmp/cache branching, opt-out flags) — direct live calls only; keep throttle + limiter + error handling.
- Probe/backfill/coverage/nightly: remove `data/raw/` artifact writes/reads and `cache_file` refs; probe writes `config/allowlist_<id>.yml`; backfill no cache-resume logic (keep idempotent upserts + budget stop).
- Tests: rewrite cache specs (zero-HTTP rerun, deterministic key, opt-outs, error-never-cached) to live-guard specs (budget stop, refusal zero-HTTP, idempotent rerun counts live); delete `tmp/cache` helpers.
- Tree: delete `data/raw/` cache files (keep dir + `.keep` only if jobs require the path); remove `FOOTBALL_CLIENT_CACHE` env references.
- Verify: `grep -rn "cache_path_for\|cache_dir\|data/raw\|FOOTBALL_CLIENT_CACHE" app/ lib/ config/ test/` returns only allowlist-yml + dir-existence guards; full suite green.

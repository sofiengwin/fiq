# Data collection
- Priority: completeness before staleness. Phase 1 = PL (39) back to earliest retrievable via probe: all teams → squads → careers + competitions/countries.
- Coverage gate: zero teams without players, zero players without careers in retrieved window (dead listed, not missing); senior filter total apps >=1 excluded from quiz with names reported, kept in DB/cache; per-season entries + dead/partial reported.
- Stale threshold: 30 days via planned last_refreshed_at on teams/players/careers (nil = stale, code deferred).
- Refresh: nightly stale-only `FootballClient` sync via planned last_refreshed_at, Solid Queue recurring daily 02:00 UTC queue team_sync cap 200 (code deferred, pre-quiz gate deferred).
- Errata: out of pipeline Phase 1. Frontend-only flag (no re-fetch queue yet).

## Plan (docs only, no build)
1. Completeness PL 39 earliest-back: P1 probe finds earliest season with data, then backfill to present. Accept: coverage zero missing in retrieved window, dead seasons listed.
2. Staleness 30-day: planned last_refreshed_at + stale?, nightly stale-only job. Accept: stale auto-refreshes. Pre-quiz gate deferred.
3. Errata (deferred, frontend-only): flag stored for review; no pipeline re-fetch in Phase 1.
4. Expand: La Liga 140, Ligue 1 61, Bundesliga 78, Serie A 135. Accept: coverage per league.

## Selected: hybrid (loop efficiency + fiq precision)
- Dev: docker compose for development work; db on host 54321 (DATABASE_URL override for host rails).
- Base: `players?team&season` paginated union per retrieved season, cache-first `data/raw/` files + throttle, rerun ~0. Job cap: allowlist seasons from probe only, no recurse past present, stop on budget.
- Stats prereq (code deferred): players dob/nationality/photo_url; careers goals mandatory, assists/cards nullable, competition_id fk. No minutes_played.
- Precision keep: transfers/teams/seasons for duration daterange + normalized teams/competitions/countries; lazy for quiz-relevant players (~180 reqs) else full (~1800).
- Governance: P1 probe ≤10 reqs gates backfill (dead seasons never bulk-pulled); per-season coverage report; review_queue removed (errata frontend-only).
- Budget: ~40 base reqs/season + precision lazy-180/full-1800 amortized; caps 500 backfill / 200 nightly; throttle 0.6s; cache-first resume; probe-gated.

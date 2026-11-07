# Project Brief: Football Intelligence Qoutient App


## Outcome
A football quiz app that tests what users know.
It uses an LLM to make 10-question quizzes. Example: it shows a club (Chelsea FC) and a country, and the user guesses the player.
Users can make quizzes using plain language. They can share quizzes with friends, and friends get the same questions.

## Non-goals
  - No tackling full project at a time

## Project Acceptance Criteria
  - Should have a way for getting all data needed to make quiz generation dynamic
  - Should have a way for making sure that data collected does not become stale
  - Users should be able to use natural language to create quizes
  - Users should be able to compete with their friends by sharing their quizes with friends
  - Users should be able to create account using Social Auth
  - Users should be able to signin using social auth
  - There should be way for users to easily submit data errata
  - The quiz generated should be able to support different formats like:
    - Multiple choice questions
    - Image choice
    - Fill in the blank
    - Matching
    - Drag into brackets

## Glossary
  api-football: A paid service for getting some football data
  Chelsea FC: A soccer football club in English Premier league
  
## Areas
- Auth - [auth.md](auth.md):
  This area will focus on authentication and authorization using sso.
  Scope: Google SSO first.
- Data collection pipeline - [data-collection.md](data-collection.md):
  This area will focus on getting data needed for the project and ensuring data doesn't become stale
  Scope: 30-day staleness + nightly sync + errata path. Build order: data first.
- Quiz frontend - [quiz.md](quiz.md):
  This area will focus on single page application that will become the new quiz frontend
  Scope: SPA target, LLM NL → preview → save (rule-based fallback). Phase 1 multiple + image-choice.
- Backend Api - [backend.md](backend.md):
  The backend that will support the quiz frontend
  Scope: JSON for NL create/fetch/attempts/leaderboard. Share link replays play_session, leaderboard by score/time.

## Seams between area
- Auth ↔ Backend: user_id links quiz_attempts/leaderboard; Google SSO + email fallback.
- Data ↔ Quiz: nightly stale heal (>30d); LLM JSON validated vs quizzes/questions/answer_options.
- Quiz SPA ↔ Backend: NL preview/save, fetch quiz/questions, submit attempts.
- Data errata → frontend flag only (no pipeline re-fetch).

## Existing contract that must not break
- Public quizzes index/show + duplicate + play_session replay + quizzes/questions/answer_options schema + email login.

## Decisions
- Goal: sharpen brief first, no code. Scope 4 areas + 6 gaps. Stack Rails 8.1 + pg.
- Auth Google-first, Apple deferred. Data 30-day, PL 39 earliest-back via probe completeness first, data-first build order.
- Quiz LLM + phase-1 formats, sharing link + leaderboard, friends graph deferred. SPA kept.


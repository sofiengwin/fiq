# Backend API
- Sharing: shareable link replays identical play_session questions.
- Competition: per-quiz leaderboard by score/time; quiz_attempts.user_id fk + share_token unique.
- Quizzes.generation_metadata jsonb (NL prompt, LLM model, seed) for same-questions share replay.
- Deferred: friends graph/invites/challenges.
- SPA contract: JSON for NL create → preview → save, fetch quiz/questions, submit attempts, leaderboard.

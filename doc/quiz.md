# Quiz frontend (SPA target)
- Generation: LLM emits structured quiz JSON validated against quizzes/questions/answer_options; 7 rule-based generators kept as fallback/seed.
- Creation: plain-language input → LLM → preview → save/share.
- Formats phase 1: multiple-choice + image-choice (extends answer_options + image_url).
- Formats phase 2 (deferred): fill-blank, matching, drag-into-brackets (needs question_type + payload + new interactions).
- Schema need: questions.question_type enum + payload jsonb; answer_options stays for choices; responses.text_answer + payload jsonb for non-choice answers.
- Data need: players dob/nationality/photo_url; careers goals/assists/cards + competition_id (no minutes).
- Sharing: link + leaderboard (see backend.md).
- Errata: SPA flag button on team/player/stint (stores reason, no auto-fix).

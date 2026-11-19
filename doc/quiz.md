# Quiz (Rails app)

Kahoot means the look and snap of a solo quiz. No live room, no join code, no host screen, no podium. One Rails app, Hotwire. No second frontend, no SPA JSON contract.

## Play

- One play screen for `/play` and a saved quiz. Save, share, and the leaderboard stay on the saved quiz. `/play` offers play again only.
- Chrome is the play loop only. Create, preview, browse, the leaderboard list, and the errata flag stay ordinary Rails screens.
- Header: question n of m, running score, streak only when above 0, countdown. Quit is a small control under the tiles, not an answer.
- Clock: 20 seconds unless the question already has its own limit. No new time picker. Timeout scores 0.
- Phone-first. Two columns at every width. Extra options wrap. Desktop is the same screen, wider, not a host layout.
- Tiles: Kahoot's four pairs only (red triangle, blue diamond, yellow circle, green square). Repeat a pair past four. The shape stays, so color is not the only signal.
- Prompt picture stays above the question and is not tappable. An answer picture sits in the tile, label under it. No picture falls back to the text tile.
- One correct answer locks on the first tap. A set shows "Select all that apply" before any tap, and the tiles toggle until Confirm. The four select-all generators stay. Do not rewrite them to force a single answer.
- Snap: a lock, a confirm, or a timeout shows the correct tile, flashes a wrong pick, shows the points just earned (including +0), updates the header total, and advances on its own after about a second and a half. No Next button.
- Motion: CSS and Stimulus only. Lock and color change in under a quarter second. Reduced motion skips the movement, not the result. No sound, no mute button.
- Score: exact match or zero. A faster correct answer is worth more. Streak stays. Partial credit does not show up in play. The `scoring_mode` column can stay. Play does not read it.
- Ending: score and count only. No breakdown, not on the snap and not one tap away. No podium.

## Create

- Generation: LLM emits structured quiz JSON validated against quizzes/questions/answer_options. The 7 rule-based generators stay as fallback and seed.
- Creation: plain language, then LLM, then preview, then save. Sending a share link saves the quiz if it is not saved yet.
- Formats phase 1: multiple-choice and image-choice (`answer_options.image_url`). Phase 2 (fill-blank, matching, drag-into-brackets) stays deferred and does not have to fit these tiles.
- Schema for phase 2, not this play screen: `questions.question_type` enum + payload jsonb. `answer_options` stays for choices. `responses.text_answer` + payload jsonb for non-choice answers.
- Data need: players dob/nationality/photo_url. Careers goals/assists/cards + competition_id. No minutes.
- Errata: flag button on team/player/stint. Stores a reason. No auto-fix.

## Invitations and leaderboard

- A share link is an invitation to play the saved quiz, not a view of a score. It opens the questions already stored on the quiz. Not a new generation.
- `quizzes.generation_metadata` jsonb (NL prompt, LLM model, seed) is a record of how the quiz was made. It is not a replay engine.
- The link can go out as soon as generation succeeds. The creator does not have to play first. A signed-in player can send their own link too, including before they have played.
- One stable link per signed-in player. Many people can open it. Everyone who opens it is compared to that sender. The phone share sheet sends it. A desktop with no share sheet copies the same link.
- A friend can play with no account. The attempt stores their score. An account is required to create a quiz and to send an invitation. A guest gets no send button.
- The comparison is taken when the friend finishes. It shows the friend's score and count beside the inviter's best finished score. Highest score wins. A tie goes to the faster attempt. If the inviter has no finished score yet, the friend sees their own score and count. No placeholder, and no coming back later to see one.
- Leaderboard: per quiz, named accounts only, ranked by score then time. `quiz_attempts.user_id` fk for signed-in attempts. A guest score stays off the list for now, lives only on that results screen, and is not claimed by signing in later. They can still open the list.
- Deferred: friends graph, in-app invites, challenges, and a list of who you invited.

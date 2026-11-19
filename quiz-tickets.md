# Quiz Tickets — Locked Kahoot Play + Invitations (Hotwire, no SPA)

Source: `doc/quiz.md` (final). Context: `quiz-brief.md` in `/Users/godwinogbara/.opencode/plan/`. Conventions: each ticket fits one builder session, independently testable, ordered so earlier unblocks later. Never write SPA/JSON API. Do NOT touch root `brief.md` / `tickets.md` (data-pipeline scoped). Do NOT delete `scoring_mode`.

Research summary: Turbo Frames scope per-question navigation + Turbo Streams/Turbo morph for header/snap updates, with tiny Stimulus controllers for lock/confirm/countdown/auto-advance is the standard Hotwire pattern (no custom templating in Stimulus). Web Share = `navigator.share({title,text,url})` guarded by feature-detect, `AbortError` = cancel, fallback chain clipboard `writeText` → manual copy field; share URL must use `_url` helper (absolute) passed via Stimulus values.

---

## Q1 — Schema foundations for play + invitations (no behavior change)

- **Title:** Add quiz play/invitation columns (image, user, metadata, phase-2 schema shells)
- **Why:** Play, tiles, leaderboard, and record-only generation cannot be built — columns/tables are missing in `db/schema.rb`.
- **Exactly what to do:**
  - Migration(s): `answer_options.image_url:string (nullable)`; `quiz_attempts.user_id:bigint nullable FK → users` + index; `quiz_attempts.invitation_id:bigint nullable FK → invitations` + index (create `invitations` first); `quizzes.generation_metadata:jsonb default {}`; `questions.question_type:string/int-enum default multiple_choice` + `questions.payload:jsonb default {}`; `responses.text_answer:text nullable` + `responses.payload:jsonb default {}`.
  - Create `invitations`: `quiz_id FK, inviter_user_id FK → users, token:string unique not-null, created_at`; unique index on `(quiz_id, inviter_user_id)` + unique index on `token`.
  - Keep `quizzes.scoring_mode` untouched. No data backfill beyond defaults.
- **Done when:** `bin/rails db:migrate` + `db:migrate:redo` round-trip clean; `db/schema.rb` shows exactly the columns/tables above; `grep -r minutes_played db/ app/models` still empty.
- **Out of scope:** Any scoring, UI, invitation logic, LLM wiring (Q2–Q12).
- **Depends on:** none.

## Q2 — Lock scoring to exact-match-or-zero + speed + streak (ignore scoring_mode in play)

- **Title:** Unify ScoreCalculator + PlaySession to exact match, speed bonus, streak, timeout zero
- **Why:** Locked scoring is exact-or-zero with faster-correct worth more; today `ScoreCalculator` does partial_credit and `PlaySession` does flat 1000 + streak with no time factor.
- **Exactly what to do:**
  - Single formula used by both paths: `correct = selected_ids.sort == correct_ids.sort` (empty = wrong); `points = 0` if wrong/timeout; else `base(question.points) * time_bonus(time_taken_ms / effective_limit) + streak handling` (faster → strictly more; document chosen curve); `new_streak = correct ? streak+1 : 0`.
  - Play path must not read `quiz.scoring_mode` (leave column + validations for non-play code). Timeout path calls same scorer with empty selection and full time.
  - Define tie-break "faster" once (recommend `completed_at - started_at`, fallback sum of `time_taken_ms`) and reuse in Q10/Q11.
- **Done when:** Unit/model test: partial multi-select → 0; exact slow vs exact fast (same question) → fast scores higher; wrong resets streak, correct increments; timeout → 0; setting `scoring_mode` to either value does not change play score.
- **Out of scope:** Any view/Stimulus/countdown changes (Q3–Q7).
- **Depends on:** Q1 (needs `user_id`/`invitation_id` present only to avoid later migration conflicts; scoring itself needs no new cols).

## Q3 — One shared play screen shell (header, prompt image, 2-col grid, Quit)

- **Title:** Extract shared play partial used by /play and saved attempts
- **Why:** Doc mandates one play screen; today `play/question.html.erb` and `quiz_attempts/_question.html.erb` are divergent layouts.
- **Exactly what to do:**
  - New shared partial (e.g. `play/_screen.html.erb` or `shared/_play_screen`) rendering: header (`Question n of m`, running `Score:`, `streak` only if >0, countdown slot), prompt `image_tag question.image_url` above text when present and never a button/link, `grid-cols-2` at every width (extra options wrap naturally), small `Quit` control under tiles (not styled as answer).
  - Wire both `PlayController#question` and `QuizAttemptsController#show` (and Turbo-frame responses) to render the same partial with locals (`question`, `progress/score/streak`, `effective_limit`).
  - Keep create/preview/browse/leaderboard-list/errata as ordinary Rails screens (no change).
- **Done when:** Visiting `/play/question` and a saved `quiz_attempt_path` shows identical header/tile/quit DOM structure (same selectors/ids for Stimulus); resizing to 360px and desktop keeps 2 columns; prompt image (when set) renders above text and is not clickable.
- **Out of scope:** Tile colors/shapes/images (Q4), lock/confirm/snap/countdown behavior (Q5–Q7).
- **Depends on:** Q1.

## Q4 — Kahoot tile system (4 color/shape pairs, answer image, motion budget)

- **Title:** Lock tiles to 4 pairs + answer image + reduced-motion CSS
- **Why:** Look must be red▲ triangle, blue◆ diamond, yellow● circle, green■ square, repeated past 4; shape must persist so color isn't the only signal.
- **Exactly what to do:**
  - Update `ApplicationHelper#answer_color_class/#answer_button_class/#answer_shape` (or successor) to exactly 4 pairs in order red-triangle, blue-diamond, yellow-circle, green-square; `index % 4` for >4 options; reconcile `Question::COLORS` 6-color legacy (keep constant for old data, map new renders to 4).
  - Tile content: if `answer_option.image_url` present show image with label under it, else text tile; answer image never a submit control by itself (whole tile is the control).
  - CSS only: lock/color change <250ms (`transition-duration ≤200ms` + test hook), `@media (prefers-reduced-motion: reduce)` disables transform/pulse but still shows final correct/wrong colors; no sound.
- **Done when:** 6-option fixture renders colors `[red,blue,yellow,green,red,blue]` with matching shapes; image-answer tile shows image + label, text-only tile unchanged; with reduced-motion emulated no transform occurs but correct tile still highlighted; no audio element or JS beep.
- **Out of scope:** Tap/confirm/snap logic (Q5–Q6).
- **Depends on:** Q3.

## Q5 — Tap-to-lock (single) + toggle-until-Confirm (multi)

- **Title:** Single locks on tap, multi toggles until Confirm, no Next
- **Why:** Core interaction: one correct locks on first tap; set shows "Select all that apply" and toggles until Confirm.
- **Exactly what to do:**
  - Stimulus controller (extend `answer-selection` or new `play-lock`): if `correct_count == 1`, first tile tap disables all tiles and submits (via Turbo) immediately; if `>1`, show "Select all that apply" badge (already in views — keep wording) and toggle `.selected` on taps, enable/show Confirm button only in multi case; single case has no submit/Confirm/Next button.
  - Server still validates exact match (never trust client `correct_count`); double-tap/double-submit is idempotent (second ignored).
  - No Next button anywhere in play loop.
- **Done when:** Single-correct fixture: one tap submits, tiles become disabled, no second tap changes payload; multi fixture: taps toggle without submitting, Confirm submits selection; "Select all that apply" appears only when `correct_count > 1`; no Next/Submit button in single mode.
- **Out of scope:** Snap reveal/auto-advance (Q6), countdown/timeout (Q7).
- **Depends on:** Q3, Q4.

## Q6 — Snap reveal + points + auto-advance ~1.5s

- **Title:** Reveal correct, flash wrong, show +points, advance automatically
- **Why:** Snap must show correct tile, flash wrong pick, show points earned including +0, update header total, advance on its own after ~1.5s.
- **Exactly what to do:**
  - On lock/confirm/timeout response (Turbo Stream or Turbo Frame replacement): add `.is-correct` to correct tile(s), `.is-wrong-pick` flash to wrongly tapped tile(s), render `+N` (or `+0`) near tiles and updated header score/streak; remove interactivity.
  - Stimulus timer auto-navigates to next question (or results when done) after ~1.5s (tolerance 1.2–1.8s); no Next button; honor reduced-motion (skip flash animation, still show final colors + points).
  - Reuse Q2 scorer so shown `+N` equals persisted `score_awarded`/`points`.
- **Done when:** Manual play: correct tap → correct tile highlighted + `+N>0` + header increments then next question loads without click; wrong tap → correct tile highlighted + picked tile flashes + `+0` shown; multi partial → treated as wrong (`+0`); auto-advance fires once (~1.5s) even if user keeps tapping.
- **Out of scope:** Countdown clock UI (Q7), endings (Q8).
- **Depends on:** Q2, Q5.

## Q7 — Countdown (question || quiz || 20) + timeout as zero + snap

- **Title:** 20s default countdown with timeout scoring zero
- **Why:** Clock is 20s unless question already has its own limit; timeout scores 0 and snaps like a lock.
- **Exactly what to do:**
  - Header countdown initial value = `question.effective_time_limit` (`question.time_limit_seconds || quiz.time_limit_seconds || 20` — already in model, keep). Stimulus `quiz-timer` (or successor) ticks each second, adds urgency styling ≤10s/≤5s (CSS only), records `time_taken_ms` hidden field for Q2 speed bonus.
  - On zero: auto-submit empty/timeout through same path as Q6 (correct tile shown, `+0`, header updated, auto-advance). No new time picker UI anywhere.
- **Done when:** Question with nil limits counts down from 20; question with `time_limit_seconds=7` counts from 7; letting clock hit 0 submits once, awards 0, shows snap + auto-advances; `time_taken_ms` for a fast answer is smaller than for a slow answer and yields higher points (Q2 curve).
- **Out of scope:** Endings, invitations (Q8–Q12).
- **Depends on:** Q3, Q6.

## Q8 — Endings: score + count only, correct follow-ups, no breakdown

- **Title:** Strip results to score + count with context links
- **Why:** Ending is score and count only; `/play` offers play-again, saved quiz offers share + leaderboard links; breakdown must disappear.
- **Exactly what to do:**
  - Rewrite `play/results` and `quiz_attempts/results` to show only total score + `X of Y correct` (keep cheerful heading, drop percentage ring if it implies breakdown, drop per-question breakdown lists and `answer_hint` exposure).
  - `/play` results: single primary `Play Again` (→ `play_path`); no save/share/leaderboard links. Saved-attempt results: `Share` + `Leaderboard` links (anchors for Q11), plus optional Retake; no breakdown.
- **Done when:** Completing either flow shows score + count with zero per-question rows/hints/percentages in HTML; `/play` page contains Play Again and no Share/Leaderboard hrefs; saved-attempt page contains Share + Leaderboard hrefs.
- **Out of scope:** Invitation/share/leaderboard behavior itself (Q9–Q11).
- **Depends on:** Q6, Q7.

## Q9 — Stable invitation link + save-on-send + auth gates

- **Title:** One stable link per signed-in player, save-on-send, guest read-only
- **Why:** Link goes out as soon as generation succeeds; creator need not play first; account required to create/send; guest gets no send button.
- **Exactly what to do:**
  - `Invitation` model: `belongs_to quiz, belongs_to inviter (User)`; auto-generate unique `token` (e.g. `SecureRandom.urlsafe_base64`); `stable_for(quiz, user)` find-or-create enforces one per (quiz, inviter).
  - Routes: invite entry `GET /i/:token` (or `quizzes/:id/invite/:token`) opening stored quiz questions as a new attempt (guest allowed, no login); `POST /quizzes/:id/invitations` (signed-in only) creates-or-returns stable link; if quiz unsaved (preview/draft id), sending saves it first then mints link.
  - UI: Share button visible only when signed-in; guests see no send affordance. Signed-in player can mint own link before ever playing.
  - `generation_metadata` write-only here: store NL prompt/model/seed on save; never read to regenerate on open (assert in code comment + test).
- **Done when:** Signed-in creator mints link twice → same URL; opening link before inviter plays works; unsaved-preview send persists quiz then returns link; signed-out visitor sees no Share/Send button but can open `/i/:token`; opening link always plays stored `questions/answer_options`, never triggers generation.
- **Out of scope:** Comparison display (Q10), leaderboard ranking (Q11), share-sheet JS (part of Q11).
- **Depends on:** Q1, Q8.

## Q10 — Invitation play (guest allowed) + inviter-best comparison

- **Title:** Guest can play via link; finish shows friend vs inviter-best
- **Why:** Friend plays with no account; attempt stored for comparison; comparison is friend score/count beside inviter's best finished, tie faster, else friend alone; no placeholder/revisit.
- **Exactly what to do:**
  - `QuizAttemptsController#create` accepts `invitation_token`: builds attempt with `quiz`, `user: Current.user (nullable)`, `invitation` link; guest attempt persists with `user_id=nil` but `invitation_id` set.
  - Results for invited attempt: load inviter best finished attempt (`where(quiz:, user: inviter, completed_at not-null).order(total_score DESC, duration ASC).first`); render side-by-side friend score/count + inviter best score/count; if inviter has none, render friend score/count alone with no placeholder/empty-state for inviter and no "check back later" copy.
  - Duration = `completed_at - started_at` (or Q2 choice) used for tie-break; faster wins ties.
- **Done when:** Guest (logged out) completes `/i/:token` → attempt row with `user_id=nil`, score stored; with inviter best present, results show both scores + winner callout (higher wins, tie → faster wins); with inviter never played, results show only friend score/count and no inviter placeholder text/link.
- **Out of scope:** Leaderboard list (Q11).
- **Depends on:** Q2, Q8, Q9.

## Q11 — Leaderboard (named only, score then time) + share-sheet/copy UI

- **Title:** Per-quiz leaderboard + phone share-sheet / desktop copy
- **Why:** Leaderboard per quiz, named accounts only, ranked score then time; guest stays off list, can still view, never claimable; phone uses share sheet, desktop copies same link.
- **Exactly what to do:**
  - Leaderboard query scope: `quiz.quiz_attempts.where.not(user_id: nil).where.not(completed_at: nil).order(total_score DESC, duration ASC)` (duration per Q2/Q10); show rank, display name, score, count correct?, time; guests excluded even if they played via invite.
  - Leaderboard page linked from saved-quiz results (Q8); viewable signed-out; signing in later never backfills guest attempts to a user (no claim path — assert with test).
  - Share Stimulus controller (`share`): values `url (absolute _url), title, text`; on click `navigator.share()` if present (catch `AbortError` as cancel, silent), else `navigator.clipboard.writeText(url)` + "Copied" confirmation, else reveal readonly input with raw URL for manual copy. Same link as Q9 in all paths.
- **Done when:** Seeded quiz with 2 named + 1 guest attempt shows only the 2 named ordered by score then faster time; guest can open leaderboard while logged out; desktop without `navigator.share` copies link and shows confirmation; mobile with share support opens native sheet; no UI offers guest-claim.
- **Out of scope:** Friends graph/invite list/challenges (explicitly deferred — do not add).
- **Depends on:** Q9, Q10.

## Q12 — Generation record-only + phase-2 schema shells + no-friends guardrails

- **Title:** generation_metadata record-only, phase-2 columns present but unused in play
- **Why:** `generation_metadata` is a record not a replay engine; phase-2 needs `question_type/payload` + `text_answer/payload` in schema but must not leak into tiles; friends graph stays deferred.
- **Exactly what to do:**
  - Creation path (NL → LLM → preview → save + 7 rule-based fallbacks): persist `{nl_prompt, llm_model, seed}` into `quizzes.generation_metadata` on save; add regression test that opening invite/leaderboard/retake never reads `generation_metadata` to build questions.
  - Keep `questions.question_type/payload` and `responses.text_answer/payload` writable at model level but unread in play screen/scorer (play reads only `answer_options` + `is_correct` + `image_url`).
  - Errata stays a flag button storing a reason on team/player/stint (no auto-fix, no pipeline re-fetch). No friends/invite-list/challenge tables or UI.
- **Done when:** Saving a quiz writes metadata with prompt/model/seed; grep shows `generation_metadata` read only in admin/show/debug views, never in play/invitation/leaderboard controllers; phase-2 columns exist but play tests with `question_type=fill_blank` still render tiles from `answer_options` (or are excluded from play without crashing); no friends tables/routes.
- **Out of scope:** Building phase-2 play UI, LLM prompt design, errata pipeline.
- **Depends on:** Q1, Q9.

---

### Build order

1. Q1 + Q2 in parallel (schema; scoring formula + tie-break definition).
2. Q3 shell → Q4 tiles → Q5 lock/confirm.
3. Q6 snap/advance → Q7 countdown/timeout → Q8 endings.
4. Q9 stable link/save-on-send → Q10 invited play + comparison → Q11 leaderboard + share UI.
5. Q12 record-only + phase-2 shells + guardrails (can overlap Q10–Q11, must land before invite QA).

### Human decisions still needed before building

- Confirm tie-break duration source (`completed_at-started_at` vs sum `time_taken_ms`) — Q2 proposes the former.
- Confirm invite path shape (`/i/:token` vs nested quiz route) and whether leaderboard URL is public-guessable or also token-scoped.
- Confirm 4-pair order/names for screen-reader labels (propose red-triangle, blue-diamond, yellow-circle, green-square) and alt text for answer images.

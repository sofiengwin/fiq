import { Controller } from "@hotwired/stimulus"

// Q5 tap-to-lock (single) + toggle-until-Confirm (multi).
//
// The server computes correct_count from real data and renders it as a
// value below; scoring still validates the exact match server-side and
// never trusts anything the client sends back (see QuizScoring).
//
// - Single (correctCount == 1): the first tile tap checks that tile,
//   freezes tiles via a locked flag + pointer-events (picked box stays
//   enabled so its value submits; others are unchecked + disabled),
//   records the elapsed time, and submits the form via Turbo immediately.
//   submitted flips only after requestSubmit dispatches so guard() does
//   not self-cancel the first submit. There
//   is no submit/Confirm/Next button in single mode.
// - Multi (correctCount > 1): taps toggle .selected on the tile without
//   submitting; the Confirm button (rendered only in multi mode, disabled
//   until at least one tile is picked) submits the selection.
// - guard (form submit action): makes double-tap / double-submit
//   idempotent client-side — the second submit is ignored.
export default class extends Controller {
  static targets = ["option", "submit"]
  static values = { correctCount: Number }

  toggle(event) {
    if (this.locked || this.submitted) {
      event.preventDefault()
      return
    }

    const checkbox = event.target
    if (!(checkbox instanceof HTMLInputElement)) return

    if (this.isSingle) {
      this.lockAndSubmit(checkbox)
    } else {
      this.toggleMulti(checkbox)
    }
  }

  guard(event) {
    if (this.submitted) {
      event.preventDefault()
      return
    }
    this.submitted = true
  }

  get isSingle() {
    return this.correctCountValue === 1
  }

  lockAndSubmit(checkbox) {
    // First (and only) tap: freeze the payload, then submit via Turbo.
    // Order matters: guard() cancels any submit while submitted is true,
    // so submitted must only flip AFTER requestSubmit dispatches. A
    // separate locked flag freezes tiles immediately for re-entrancy.
    // The picked box stays enabled (disabled controls are not submitted,
    // so disabling it would strip selected_ids from the POST); the other
    // boxes are unchecked + disabled and every tile is made inert via
    // pointer-events + the locked flag.
    if (this.locked) return
    this.locked = true
    this.recordTime()

    checkbox.checked = true

    this.optionTargets.forEach((option) => {
      const box = option.querySelector("input[type='checkbox']")
      const tile = option.querySelector(".play-tile")
      if (!box) return
      if (box !== checkbox) {
        box.checked = false
        box.disabled = true
      }
      option.style.pointerEvents = "none"
      if (tile) {
        // Q4 lock visuals stay; .selected marks the locked pick (Q5).
        tile.classList.toggle("selected", box.checked)
        tile.classList.toggle("ring-4", box.checked)
        tile.classList.toggle("ring-white", box.checked)
        tile.classList.toggle("scale-105", box.checked)
      }
    })

    this.element.classList.add("is-locked")
    this.element.requestSubmit()
    this.submitted = true
  }

  toggleMulti(checkbox) {
    const tile = checkbox.closest("label")?.querySelector(".play-tile")
    if (tile) {
      // Q4 lock visuals stay; .selected marks each toggled tile (Q5).
      tile.classList.toggle("selected", checkbox.checked)
      tile.classList.toggle("ring-4", checkbox.checked)
      tile.classList.toggle("ring-white", checkbox.checked)
      tile.classList.toggle("scale-105", checkbox.checked)
    }
    this.updateConfirm()
  }

  updateConfirm() {
    if (!this.hasSubmitTarget) return
    const anyChecked = this.optionTargets.some((option) => {
      const box = option.querySelector("input[type='checkbox']")
      return box && box.checked
    })
    this.submitTarget.disabled = !anyChecked
  }

  recordTime() {
    // quiz-timer owns the clock; reuse it so time_taken_ms matches Q2/Q7.
    const screen = this.element.closest("#play-screen")
    if (screen) {
      const timer = this.application.getControllerForElementAndIdentifier(screen, "quiz-timer")
      if (timer) {
        timer.submit()
        return
      }
    }
    // Fallback: leave the hidden field at its current value.
  }
}

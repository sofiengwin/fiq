import { Controller } from "@hotwired/stimulus"

// Q7 countdown: ticks each second from secondsValue (the question's
// effective_time_limit — question.time_limit_seconds ||
// quiz.time_limit_seconds || 20s default — rendered into
// #play-countdown by the shared play screen), adds urgency styling at
// <=10s (is-low) and <=5s (is-critical) which is visual-only and owned
// by CSS, records the elapsed ms into the hidden timeTaken field so the
// Q2 speed curve scores faster correct answers higher, and on zero
// auto-submits an empty (timeout) selection exactly once through the
// same Q6 snap path as a lock (the server scores 0 via
// process_timeout!/submit_timeout and renders the snap + auto-advance).
export default class extends Controller {
  static targets = ["display", "timeTaken", "form", "submit"]
  static values = { seconds: Number }

  connect() {
    this.startTime = Date.now()
    this.remaining = this.secondsValue
    this.submitted = false
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    this.stop()
  }

  stop() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  }

  tick() {
    this.displayTarget.textContent = this.remaining

    // Urgency is CSS-only: JS toggles state classes, visuals live in CSS.
    this.displayTarget.classList.toggle("is-low", this.remaining <= 10)
    this.displayTarget.classList.toggle("is-critical", this.remaining <= 5)

    if (this.remaining <= 0) {
      this.autoSubmit()
    } else {
      this.remaining -= 1
    }
  }

  // Manual submit path (single-tap lock / Confirm): freeze the clock and
  // record the elapsed ms for the Q2 speed bonus.
  submit() {
    if (this.hasTimeTakenTarget && !this.submitted) {
      this.timeTakenTarget.value = Date.now() - this.startTime
    }
    this.submitted = true
    this.stop()
  }

  autoSubmit() {
    // Timeout: exactly one empty submit through the snap path. A manual
    // lock/Confirm that won the race already submitted — never fire twice.
    if (this.submitted) return
    if (this.formLocked()) return
    this.submitted = true
    this.stop()

    // Full-limit elapsed + no selection = timeout as zero server-side.
    if (this.hasTimeTakenTarget) {
      this.timeTakenTarget.value = this.secondsValue * 1000
    }
    const form = this.hasFormTarget ? this.formTarget : this.element.querySelector("form")
    if (!form) return
    form.querySelectorAll("input[type='checkbox']:checked").forEach((box) => {
      box.checked = false
    })
    form.requestSubmit()
  }

  formLocked() {
    const form = this.hasFormTarget ? this.formTarget : this.element.querySelector("form")
    if (!form) return false
    if (form.classList.contains("is-locked")) return true
    const lock = this.application.getControllerForElementAndIdentifier(form, "answer-selection")
    return !!(lock && (lock.submitted || lock.locked))
  }
}

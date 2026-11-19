import { Controller } from "@hotwired/stimulus"

// Q6 snap auto-advance: after the snap reveal (~1.5s) navigates once to the
// next question (or results when done). Fires exactly once even if the user
// keeps tapping — there is nothing to tap (snap renders no form), and the
// `advanced` flag guards double timeouts.
//
// Reduced motion is honored in CSS (flash animation disabled, final
// colors + points still shown); the timer itself always fires so play
// never stalls.
export default class extends Controller {
  static values = {
    url: String,
    delay: { type: Number, default: 1500 },
    frame: String
  }

  connect() {
    this.advanced = false
    const delay = this.hasDelayValue ? this.delayValue : 1500
    this.timer = setTimeout(() => this.advance(), delay)
  }

  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  advance() {
    if (this.advanced) return
    this.advanced = true
    if (!this.urlValue) return

    if (this.hasFrameValue && this.frameValue) {
      const frame = document.getElementById(this.frameValue)
      if (frame) {
        frame.src = this.urlValue
        return
      }
    }

    if (window.Turbo && typeof window.Turbo.visit === "function") {
      window.Turbo.visit(this.urlValue)
    } else {
      window.location.href = this.urlValue
    }
  }
}

import { Controller } from "@hotwired/stimulus"

// Manages the quiz timer countdown and auto-submission
export default class extends Controller {
  static targets = ["display", "timeTaken", "form", "submit"]
  static values = { seconds: Number }

  connect() {
    this.startTime = Date.now()
    this.remaining = this.secondsValue
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.interval) {
      clearInterval(this.interval)
    }
  }

  tick() {
    this.displayTarget.textContent = this.remaining

    // Add urgency styling when time is running low
    if (this.remaining <= 5) {
      this.displayTarget.classList.add("text-red-500", "animate-pulse")
    } else if (this.remaining <= 10) {
      this.displayTarget.classList.add("text-yellow-400")
    }

    if (this.remaining <= 0) {
      clearInterval(this.interval)
      this.autoSubmit()
    } else {
      this.remaining -= 1
    }
  }

  submit() {
    // Record time taken before form submission
    if (this.hasTimeTakenTarget) {
      this.timeTakenTarget.value = Date.now() - this.startTime
    }
  }

  autoSubmit() {
    this.submit()
    // Find and submit the form
    if (this.hasFormTarget) {
      this.formTarget.requestSubmit()
    } else {
      const form = this.element.querySelector("form")
      if (form) {
        form.requestSubmit()
      }
    }
  }
}

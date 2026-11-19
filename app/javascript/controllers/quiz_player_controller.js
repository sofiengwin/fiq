import { Controller } from "@hotwired/stimulus"

// Quiz player setup (tile feedback is visual-only by design).
export default class extends Controller {
  connect() {
    console.log("Quiz player connected")
  }

  disconnect() {
    // Cleanup if needed
  }
}

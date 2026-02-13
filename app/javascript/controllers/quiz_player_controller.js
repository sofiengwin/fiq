import { Controller } from "@hotwired/stimulus"

// Provides overall quiz player functionality
export default class extends Controller {
  connect() {
    // Play entrance sound/animation if needed
    console.log("Quiz player connected")
  }

  disconnect() {
    // Cleanup if needed
  }
}

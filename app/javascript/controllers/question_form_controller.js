import { Controller } from "@hotwired/stimulus"

// Handles dynamic question form interactions
export default class extends Controller {
  static targets = ["answers"]

  connect() {
    console.log("Question form connected")
  }

  addAnswer(event) {
    event.preventDefault()
    // This could be implemented with a template for adding more answers dynamically
    console.log("Add answer clicked")
  }
}

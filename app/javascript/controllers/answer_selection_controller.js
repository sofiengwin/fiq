import { Controller } from "@hotwired/stimulus"

// Handles answer selection visual feedback
export default class extends Controller {
  static targets = ["option"]

  toggle(event) {
    const checkbox = event.target
    const optionDiv = checkbox.closest("label").querySelector("div")
    
    if (checkbox.checked) {
      optionDiv.classList.add("ring-4", "ring-white", "scale-105")
    } else {
      optionDiv.classList.remove("ring-4", "ring-white", "scale-105")
    }
  }

  // For single-select mode (optional future use)
  selectOne(event) {
    // Uncheck all other options
    this.optionTargets.forEach(option => {
      const checkbox = option.querySelector("input[type='checkbox']")
      const div = option.querySelector("div")
      if (checkbox !== event.target) {
        checkbox.checked = false
        div.classList.remove("ring-4", "ring-white", "scale-105")
      }
    })
    
    this.toggle(event)
  }
}

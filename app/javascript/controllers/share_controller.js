import { Controller } from "@hotwired/stimulus"

// Q11 share sheet / desktop copy fallback. Values carry the SAME absolute
// invite link as Q9 (an `_url` helper passed in from the view).
//
// On click:
//   1. `navigator.share()` when present (phones) opens the native sheet.
//      An `AbortError` is the user cancelling — silent, nothing else happens.
//   2. Otherwise `navigator.clipboard.writeText(url)` (desktop) copies the
//      link and shows a "Copied" confirmation.
//   3. Otherwise (no share, no clipboard) a readonly input with the raw URL
//      is revealed for manual copy.
export default class extends Controller {
  static values = {
    url: String,
    title: String,
    text: String
  }
  static targets = ["status", "fallback", "fallbackInput", "button"]

  connect() {
    if (this.hasFallbackInputTarget && this.urlValue) {
      this.fallbackInputTarget.value = this.urlValue
    }
    // No share sheet and no clipboard: reveal the manual-copy field now.
    if (!this.canShare && !this.canCopy) {
      this.showFallback()
    }
  }

  get canShare() {
    return typeof navigator !== "undefined" && typeof navigator.share === "function"
  }

  get canCopy() {
    return (
      typeof navigator !== "undefined" &&
      !!(navigator.clipboard && typeof navigator.clipboard.writeText === "function")
    )
  }

  async share(event) {
    if (event) event.preventDefault()

    if (this.canShare) {
      try {
        await navigator.share({
          title: this.titleValue,
          text: this.textValue,
          url: this.urlValue
        })
        return
      } catch (error) {
        // Cancelling the sheet is silent; any other failure falls through
        // to the clipboard / manual-copy fallbacks below.
        if (error && error.name === "AbortError") return
      }
    }

    if (this.canCopy) {
      try {
        await navigator.clipboard.writeText(this.urlValue)
        this.confirmCopy()
        return
      } catch {
        // Clipboard denied — fall through to manual copy.
      }
    }

    this.showFallback()
  }

  confirmCopy() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Copied"
    }
  }

  showFallback() {
    if (this.hasFallbackInputTarget) {
      this.fallbackInputTarget.value = this.urlValue
    }
    if (this.hasFallbackTarget) {
      this.fallbackTarget.hidden = false
    }
    if (this.hasFallbackInputTarget) {
      this.fallbackInputTarget.focus()
      this.fallbackInputTarget.select()
    }
  }
}

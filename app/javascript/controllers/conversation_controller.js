import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "form", "path", "messages", "submit"]

  connect() {
    this.mutationObserver = new MutationObserver((mutations) => this.handleMutation(mutations))
    this.mutationObserver.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.mutationObserver.disconnect()
  }

  handleKeyDown(event) {
    if (event.key === 'Enter' && !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault()
      this.submitMessage()
    }
  }

  disableForm() {
    this.submitTarget.disabled = true
  }

  handleSubmitEnd(event) {
    this.submitTarget.disabled = false
    if (event.detail.success) {
      this.textareaTarget.value = ''
    }
  }

  handleMutation(mutations) {
    this.updateUrl()
    if (this.mutationAffectsMessages(mutations)) {
      this.scrollToLatest()
    }
  }

  mutationAffectsMessages(mutations) {
    if (!this.hasMessagesTarget) return false
    return mutations.some((mutation) =>
      mutation.target === this.messagesTarget ||
      this.messagesTarget.contains(mutation.target) ||
      mutation.target.contains(this.messagesTarget)
    )
  }

  submitMessage() {
    if (this.submitTarget.disabled || !this.textareaTarget.value.trim()) return
    this.formTarget.requestSubmit()
  }

  updateUrl() {
    if (this.hasPathTarget && this.pathTarget.value) {
      window.history.replaceState(null, '', this.pathTarget.value)
    }
  }

  scrollToLatest() {
    if (!this.hasMessagesTarget) return
    const lastMessage = this.messagesTarget.lastElementChild
    lastMessage?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }
}

import { Controller } from "@hotwired/stimulus"
import { subscribeConversation } from "controllers/conversation_stream"

export default class extends Controller {
  static targets = ["textarea", "form", "path", "messages", "submit", "scroll"]

  connect() {
    this.subscribe()
    this.mutationObserver = new MutationObserver((mutations) => this.handleMutation(mutations))
    this.mutationObserver.observe(this.element, { childList: true, subtree: true })
    requestAnimationFrame(() => this.scrollToLatest())
  }

  disconnect() {
    this.mutationObserver.disconnect()
  }

  subscribe() {
    const publicId = this.element.dataset.conversationPublicId
    if (publicId) subscribeConversation(publicId)
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
    this.syncPublicId(mutations)
    if (this.mutationAffectsMessages(mutations)) {
      this.scrollToLatest()
    }
  }

  syncPublicId(mutations) {
    const added = mutations.some((m) =>
      Array.from(m.addedNodes).some((n) => n.nodeType === Node.ELEMENT_NODE && n.id === 'conversation-hidden-fields')
    )
    if (!added) return
    const publicId = this.element.querySelector('input[name="conversation_public_id"]')?.value
    if (publicId && publicId !== this.element.dataset.conversationPublicId) {
      this.element.dataset.conversationPublicId = publicId
      this.subscribe()
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
    if (!this.hasScrollTarget) return
    this.scrollTarget.scrollTop = this.scrollTarget.scrollHeight
    this.formTarget.scrollIntoView({ block: 'end' })
  }
}

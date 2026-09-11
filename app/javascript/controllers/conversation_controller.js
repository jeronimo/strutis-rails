import { Controller } from "@hotwired/stimulus"
import { subscribeConversation } from "controllers/conversation_stream"

export default class extends Controller {
  static targets = ["textarea", "form", "path", "messages", "submit", "scroll", "modelSelect", "thinking", "reasoningEffort", "contextWarning"]

  connect() {
    this.subscribe()
    this.models = JSON.parse(this.modelSelectTarget.dataset.conversationModels)
    this.contextTokens = Number(this.modelSelectTarget.dataset.conversationContextTokens) || 0
    this.compactThreshold = Number(this.modelSelectTarget.dataset.conversationCompactThreshold)
    if (!Number.isFinite(this.compactThreshold) || this.compactThreshold <= 0) {
      console.warn(`[conversation] invalid compact_threshold (${this.compactThreshold}); context guard disabled`)
    }
    this.currentModel = this.modelSelectTarget.value
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
    if (this.compactDraft !== undefined) {
      this.textareaTarget.value = this.compactDraft
      this.compactDraft = undefined
      return
    }
    if (event.detail.success) {
      this.textareaTarget.value = ''
    }
  }

  modelChanged() {
    const model = this.modelSelectTarget.value
    const metadata = this.models[model]
    if (!metadata) return
    const limit = metadata.context_length ? Math.floor(metadata.context_length * this.compactThreshold) : null
    if (this.contextTokens > 0 && limit !== null && this.contextTokens > limit) {
      this.modelSelectTarget.value = this.currentModel
      this.showContextWarning(model, limit)
      return
    }
    this.currentModel = model
    this.applyModelOptions(model)
    this.contextWarningTarget.classList.add('d-none')
  }

  applyModelOptions(model) {
    const metadata = this.models[model]
    if (!metadata) return
    const thinkingInput = this.thinkingTarget.querySelector('input')
    const supportsThinking = Boolean(metadata.supports_thinking)
    this.thinkingTarget.classList.toggle('d-none', !supportsThinking)
    thinkingInput.checked = supportsThinking ? Boolean(metadata.default_thinking) : false
    const options = metadata.reasoning_effort_options || []
    this.reasoningEffortTarget.classList.toggle('d-none', options.length === 0)
    if (options.length > 0) {
      const current = this.reasoningEffortTarget.value
      this.reasoningEffortTarget.innerHTML = ''
      options.forEach((effort) => {
        const option = document.createElement('option')
        option.value = effort
        option.textContent = effort
        this.reasoningEffortTarget.appendChild(option)
      })
      const fallback = options.includes(metadata.default_reasoning_effort) ? metadata.default_reasoning_effort : options[0]
      this.reasoningEffortTarget.value = options.includes(current) ? current : fallback
    } else {
      this.reasoningEffortTarget.value = ''
    }
  }

  showContextWarning(model, limit) {
    this.contextWarningTarget.querySelector('.context-warning-message').textContent =
      `Context (${this.contextTokens.toLocaleString()} tokens) exceeds ${model}'s usable limit (${limit.toLocaleString()} tokens).`
    this.contextWarningTarget.classList.remove('d-none')
  }

  compact() {
    this.compactDraft = this.textareaTarget.value
    this.textareaTarget.value = '/compact'
    this.formTarget.requestSubmit()
  }

  handleMutation(mutations) {
    this.updateUrl()
    this.syncPublicId(mutations)
    this.syncContextTokens(mutations)
    if (this.mutationAffectsMessages(mutations)) {
      this.scrollToLatest()
    }
  }

  syncContextTokens(mutations) {
    const touched = mutations.some((m) =>
      Array.from(m.addedNodes).some((n) => n.nodeType === Node.ELEMENT_NODE && (n.matches('[data-context-tokens]') || n.querySelector('[data-context-tokens]')))
    )
    if (!touched) return
    const usage = this.element.querySelector('[data-context-tokens]')
    if (usage) this.contextTokens = Number(usage.dataset.contextTokens) || 0
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

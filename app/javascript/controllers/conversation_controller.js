import { Controller } from "@hotwired/stimulus"
import { subscribeConversation } from "controllers/conversation_stream"

export default class extends Controller {
  static targets = [
    "textarea", "form", "path", "messages", "submit", "scroll",
    "modelButton", "modelModal", "modelList", "modelName", "modelHidden",
    "thinking", "reasoningEffort", "thinkingHidden", "reasoningEffortHidden",
    "contextWarning", "attachments", "mic", "paperclip",
    "contextUsage", "contextTokens", "contextWindow", "contextPercent",
    "transcribeProgress"
  ]

  connect() {
    this.subscribe()
    this.models = JSON.parse(this.element.dataset.conversationModels)
    this.contextTokens = Number(this.element.dataset.conversationContextTokens) || 0
    this.compactThreshold = Number(this.element.dataset.conversationCompactThreshold)
    if (!Number.isFinite(this.compactThreshold) || this.compactThreshold <= 0) {
      console.warn(`[conversation] invalid compact_threshold (${this.compactThreshold}); context guard disabled`)
    }
    this.currentModel = this.modelHiddenTarget.value
    this.mediaRecorder = null
    this.audioChunks = []
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
      if (this.hasAttachmentsTarget) this.attachmentsTarget.value = ''
    }
  }

  openModelModal() {
    this.syncModalToCurrentModel()
    bootstrap.Modal.getOrCreateInstance(this.modelModalTarget).show()
  }

  saveModelModal() {}

  syncModalToCurrentModel() {
    const option = this.modelListTarget.querySelector(`input[value="${this.currentModel}"]`)
    if (option) option.checked = true
    this.applyModelOptions(this.currentModel)
  }

  modelOptionChanged(event) {
    const model = event.target.value
    const metadata = this.models[model]
    if (!metadata) return
    const limit = metadata.context_length ? Math.floor(metadata.context_length * this.compactThreshold) : null
    if (this.contextTokens > 0 && limit !== null && this.contextTokens > limit) {
      this.showContextWarning(model, limit)
      return
    }
    this.currentModel = model
    this.modelHiddenTarget.value = model
    this.modelNameTarget.textContent = this.models[model]?.display_name || model
    this.applyModelOptions(model)
    this.updateContextUsage()
    this.contextWarningTarget.classList.add('d-none')
  }

  thinkingOptionChanged(event) {
    this.thinkingHiddenTarget.value = event.target.checked ? '1' : ''
  }

  reasoningEffortOptionChanged(event) {
    this.reasoningEffortHiddenTarget.value = event.target.value
  }

  applyModelOptions(model) {
    const metadata = this.models[model]
    if (!metadata) return
    const thinkingInput = this.thinkingTarget.querySelector('input')
    const supportsThinking = Boolean(metadata.supports_thinking)
    this.thinkingTarget.classList.toggle('d-none', !supportsThinking)
    thinkingInput.checked = supportsThinking ? Boolean(metadata.default_thinking) : false
    this.thinkingHiddenTarget.value = thinkingInput.checked ? '1' : ''
    const options = metadata.reasoning_effort_options || []
    this.reasoningEffortTarget.classList.toggle('d-none', options.length === 0)
    const select = this.reasoningEffortTarget.querySelector('select')
    if (options.length > 0) {
      const current = select.value
      select.innerHTML = ''
      options.forEach((effort) => {
        const option = document.createElement('option')
        option.value = effort
        option.textContent = effort
        select.appendChild(option)
      })
      const fallback = options.includes(metadata.default_reasoning_effort) ? metadata.default_reasoning_effort : options[0]
      select.value = options.includes(current) ? current : fallback
    } else {
      select.value = ''
    }
    this.reasoningEffortHiddenTarget.value = select.value
  }

  showContextWarning(model, limit) {
    const warning = this.contextWarningTarget
    warning.querySelector('.context-warning-message').textContent =
      `Context (${this.contextTokens.toLocaleString()} tokens) exceeds ${model}'s usable limit (${limit.toLocaleString()} tokens).`
    warning.querySelector('button').classList.remove('d-none')
    warning.classList.remove('d-none')
  }

  showImageWarning() {
    const warning = this.contextWarningTarget
    warning.querySelector('.context-warning-message').textContent =
      'The selected model cannot process images. Remove the image or choose a different model.'
    warning.querySelector('button').classList.add('d-none')
    warning.classList.remove('d-none')
  }

  compact() {
    this.compactDraft = this.textareaTarget.value
    this.textareaTarget.value = '/compact'
    this.formTarget.requestSubmit()
  }

  updateContextUsage() {
    if (!this.hasContextUsageTarget) return
    const metadata = this.models[this.currentModel]
    const window = metadata?.context_length || 0
    this.contextTokensTarget.textContent = this.contextTokens.toLocaleString()
    this.contextWindowTarget.textContent = window.toLocaleString()
    this.contextPercentTarget.textContent = window > 0 ? `${Math.round(this.contextTokens / window * 100)}%` : ''
  }

  async toggleRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state === 'recording') {
      this.mediaRecorder.stop()
      return
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.mediaRecorder = new MediaRecorder(stream)
      this.audioChunks = []
      this.mediaRecorder.ondataavailable = (event) => { if (event.data.size > 0) this.audioChunks.push(event.data) }
      this.mediaRecorder.onstop = () => this.handleRecordingStop()
      this.mediaRecorder.start()
      this.micTarget.classList.add('recording')
    } catch (error) {
      console.error('[conversation] recording failed', error)
    }
  }

  handleRecordingStop() {
    this.mediaRecorder.stream.getTracks().forEach((track) => track.stop())
    this.micTarget.classList.remove('recording')
    this.transcribeProgressTarget.classList.remove('d-none')
    const blob = new Blob(this.audioChunks, { type: this.mediaRecorder.mimeType })
    this.transcribeAndSubmit(blob)
  }

  async transcribeAndSubmit(blob) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const transcribeFormData = new FormData()
    transcribeFormData.append('file', blob, 'recording.webm')
    const response = await fetch(this.element.dataset.conversationTranscribePath, {
      method: 'POST',
      body: transcribeFormData,
      headers: { 'X-CSRF-Token': token }
    })
    this.transcribeProgressTarget.classList.add('d-none')
    if (!response.ok) throw new Error(`Transcription failed: ${response.status}`)
    const { text } = await response.json()
    if (!text) return

    const messageFormData = new FormData(this.formTarget)
    messageFormData.set('message', text)
    const name = `recording-${Date.now()}.webm`
    messageFormData.append('attachments[]', new File([blob], name, { type: blob.type }))

    const createResponse = await fetch(this.formTarget.action, {
      method: 'POST',
      body: messageFormData,
      headers: { 'X-CSRF-Token': token }
    })
    const html = await createResponse.text()
    document.body.insertAdjacentHTML('beforeend', html)
  }

  hasImageAttachments() {
    return Array.from(this.attachmentsTarget.files).some((file) => file.type.startsWith('image/'))
  }

  submitMessage() {
    if (this.submitTarget.disabled) return
    const hasText = this.textareaTarget.value.trim() !== ''
    const hasFiles = this.hasAttachmentsTarget && this.attachmentsTarget.files.length > 0
    if (!hasText && !hasFiles) return
    const metadata = this.models[this.currentModel]
    if (metadata && !metadata.supports_image_input && this.hasImageAttachments()) {
      this.showImageWarning()
      return
    }
    this.formTarget.requestSubmit()
  }

  handleAttachmentsChange() {
    if (this.attachmentsTarget.files.length > 0) {
      this.submitMessage()
    }
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
    if (usage) {
      this.contextTokens = Number(usage.dataset.contextTokens) || 0
      this.updateContextUsage()
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

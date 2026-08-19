import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "model"]

  connect() {
    this.textareaTarget.addEventListener('input', this.resizeTextarea.bind(this))
    this.textareaTarget.addEventListener('keydown', this.handleKeyDown.bind(this))
    this.resizeTextarea()
  }

  resizeTextarea() {
    this.textareaTarget.style.height = 'auto'
    this.textareaTarget.style.height = this.textareaTarget.scrollHeight + 'px'
  }

  handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      this.submitMessage()
    }
  }

  submitMessage() {
    const message = this.textareaTarget.value.trim()
    if (!message) return

    if (!this.hasModelTarget || !this.modelTarget.value) {
      alert('Please select a model')
      return
    }

    const messagesContainer = document.getElementById('messages')
    if (messagesContainer) {
      const userMsg = document.createElement('div')
      userMsg.className = 'row mb-3'
      userMsg.innerHTML = `
        <div class="col-2"><strong class="text-primary">You</strong></div>
        <div class="col-10"><div class="p-2 rounded bg-light white-space-pre-wrap">${this.escapeHtml(message)}</div></div>
      `
      messagesContainer.appendChild(userMsg)
      messagesContainer.scrollTop = messagesContainer.scrollHeight
    }

    this.textareaTarget.value = ''
    this.resizeTextarea()

    const formData = new FormData()
    formData.append('message', message)
    formData.append('model', this.modelTarget.value)

    const form = this.element.closest('form')
    const url = form.action

    fetch(url, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.error) {
        alert(data.error)
        return
      }

      if (messagesContainer) {
        const aiMsg = document.createElement('div')
        aiMsg.className = 'row mb-3'
        aiMsg.innerHTML = `
          <div class="col-2"><strong class="text-success">AI</strong></div>
          <div class="col-10"><div class="p-2 rounded bg-light white-space-pre-wrap">${this.escapeHtml(data.response)}</div></div>
        `
        messagesContainer.appendChild(aiMsg)
        messagesContainer.scrollTop = messagesContainer.scrollHeight
      }
    })
    .catch(error => {
      console.error('Error:', error)
      alert('An error occurred')
    })
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

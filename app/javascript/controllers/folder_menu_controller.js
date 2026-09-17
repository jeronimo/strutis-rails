import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "form", "input", "toggle"]

  connect() {
    this.dropdown = window.bootstrap.Dropdown.getOrCreateInstance(this.toggleTarget)
  }

  disconnect() {
    this.dropdown.dispose()
  }

  rename() {
    this.inputTarget.value = this.nameTarget.textContent
    this.nameTarget.classList.add('d-none')
    this.formTarget.classList.remove('d-none')
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  handleKeydown(event) {
    if (event.key === 'Enter') {
      event.preventDefault()
      this.submit()
    } else if (event.key === 'Escape') {
      event.preventDefault()
      this.cancel()
    }
  }

  handleBlur() {
    if (this.formTarget.classList.contains('d-none')) return
    if (this.inputTarget.value.trim() !== this.nameTarget.textContent) {
      this.submit()
    } else {
      this.cancel()
    }
  }

  submit() {
    this.formTarget.requestSubmit()
    this.cancel()
  }

  cancel() {
    this.formTarget.classList.add('d-none')
    this.nameTarget.classList.remove('d-none')
  }
}

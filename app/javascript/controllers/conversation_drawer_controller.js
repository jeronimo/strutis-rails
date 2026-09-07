import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "backdrop", "toggle"]

  connect() {
    this.drawerTarget.addEventListener('click', (event) => {
      if (event.target.closest('a')) this.close()
    })
    this.backdropTarget.addEventListener('click', () => this.close())
  }

  toggle() {
    this.open = !this.isOpen
  }

  close() {
    this.open = false
  }

  get isOpen() {
    return document.body.classList.contains('conversation-drawer-open')
  }

  set open(value) {
    document.body.classList.toggle('conversation-drawer-open', value)
    if (this.hasToggleTarget) this.toggleTarget.setAttribute('aria-expanded', String(value))
  }
}

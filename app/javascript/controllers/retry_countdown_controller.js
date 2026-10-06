import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]
  static values = { seconds: { type: Number, default: 0 } }

  connect() {
    this.remaining = this.secondsValue
    this.render()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    this.remaining = Math.max(0, this.remaining - 1)
    this.render()
  }

  render() {
    this.countTarget.textContent = this.remaining
  }
}

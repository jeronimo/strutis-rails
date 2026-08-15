import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { interval: { type: Number, default: 500 } }

  connect() {
    this.getLabel = this.getLabel.bind(this)
    this.getLabel()
    this.intervalId = setInterval(this.getLabel, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.intervalId)
  }

  async getLabel() {
    try {
      const response = await fetch("/latency")
      const data = await response.json()

      if (data.latency) {
        this.labelTarget.textContent = `${data.latency}ms`
        this.labelTarget.style.color = 'green'
      } else {
        this.labelTarget.textContent = `Error: ${data.error || 'Failed to fetch'}`
        this.labelTarget.style.color = 'red'
      }
    } catch (error) {
      this.labelTarget.textContent = `Error: ${error.message}`
      this.labelTarget.style.color = 'red'
    }
  }
}

import { Controller } from "@hotwired/stimulus"
import { consumer } from "controllers/conversation_stream"

export default class extends Controller {
  connect() {
    this.subscription ||= consumer.subscriptions.create({ channel: "UserChannel" }, {
      received: (data) => {
        Turbo.renderStreamMessage(data)
        this.chimeIfUnread(data)
      }
    })
    this._onVisibility = () => this.flushPendingChime()
    document.addEventListener('visibilitychange', this._onVisibility)
  }

  disconnect() {
    document.removeEventListener('visibilitychange', this._onVisibility)
  }

  chimeIfUnread(data) {
    if (typeof data !== 'string' || !data.includes('conversation-unread-')) return
    const stream = new DOMParser().parseFromString(data, 'text/html').querySelector('turbo-stream[target^="conversation-unread-"]')
    if (!stream) return
    const badge = stream.querySelector('template')?.content.querySelector('.conversation-unread')
    if (badge?.classList.contains('d-none')) return
    if (document.hidden) {
      this._pendingChime = true
      return
    }
    this.playChime()
  }

  flushPendingChime() {
    if (!this._pendingChime || document.hidden) return
    this._pendingChime = false
    this.playChime()
  }

  playChime() {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    this.audioContext ||= new AudioContextClass()
    if (this.audioContext.state === 'suspended') this.audioContext.resume().catch(() => {})
    const start = this.audioContext.currentTime
    ;[ [ 523.25, 0 ], [ 659.25, 0.12 ], [ 783.99, 0.24 ] ].forEach(([ frequency, offset ]) => {
      const oscillator = this.audioContext.createOscillator()
      const gain = this.audioContext.createGain()
      oscillator.type = 'sine'
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, start + offset)
      gain.gain.exponentialRampToValueAtTime(0.35, start + offset + 0.015)
      gain.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.11)
      oscillator.connect(gain).connect(this.audioContext.destination)
      oscillator.start(start + offset)
      oscillator.stop(start + offset + 0.12)
    })
  }
}

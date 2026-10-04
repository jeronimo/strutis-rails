import { Controller } from "@hotwired/stimulus"
import { consumer } from "controllers/conversation_stream"

export default class extends Controller {
  connect() {
    this.subscription ||= consumer.subscriptions.create({ channel: "UserChannel" }, {
      received(data) {
        Turbo.renderStreamMessage(data)
      }
    })
  }
}

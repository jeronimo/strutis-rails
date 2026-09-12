import { createConsumer } from "@rails/actioncable/src"

const consumer = createConsumer()
let currentSubscription = null
let currentPublicId = null

export function subscribeConversation(publicId) {
  if (!publicId) return
  if (publicId === currentPublicId && currentSubscription) return

  const oldSubscription = currentSubscription
  const oldPublicId = currentPublicId

  const newSubscription = consumer.subscriptions.create(
    { channel: "ConversationChannel", public_id: publicId },
    {
      received(data) {
        applyStream(data)
      },
      connected() {
        currentSubscription = newSubscription
        currentPublicId = publicId
        if (oldSubscription && oldPublicId !== publicId) {
          oldSubscription.unsubscribe()
        }
      }
    }
  )
}

export function unsubscribeConversation() {
  if (!currentSubscription) return
  currentSubscription.unsubscribe()
  currentSubscription = null
  currentPublicId = null
}

function applyStream(data) {
  if (typeof data === 'string') {
    const stream = new DOMParser().parseFromString(data, 'text/html').querySelector('turbo-stream')
    if (stream && stream.getAttribute('action') === 'append') {
      const target = document.getElementById(stream.getAttribute('target'))
      if (target && target.dataset.final === 'true') return
    }
  }
  Turbo.renderStreamMessage(data)
}

document.addEventListener("turbo:load", () => {
  if (!document.querySelector(".chat-conversation")) {
    unsubscribeConversation()
  }
})

window.addEventListener("pagehide", (event) => {
  if (event.persisted) return
  unsubscribeConversation()
})

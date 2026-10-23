import { createConsumer } from "@rails/actioncable/src"

export const consumer = createConsumer()
let currentSubscription = null
let currentPublicId = null
let watching = false

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
        if (oldSubscription && oldPublicId !== publicId) {
          oldSubscription.unsubscribe()
        }
      }
    }
  )
  currentSubscription = newSubscription
  currentPublicId = publicId
}

export function setWatching(value) {
  watching = value
}

export function readBadgeIfWatched(data) {
  if (watching && typeof data === 'string' && data.includes(`conversation-unread-${currentPublicId}`)) {
    performConversation('read')
    return true
  }
  return false
}

export function performConversation(action) {
  currentSubscription?.perform(action)
}

export function unsubscribeConversation() {
  if (!currentSubscription) return
  currentSubscription.unsubscribe()
  currentSubscription = null
  currentPublicId = null
}

function applyStream(data) {
  if (typeof data === 'string') {
    const stream = new DOMParser().parseFromString(data, 'text/html').querySelector('turbo-stream[action="append"]')
    if (stream) {
      const target = document.getElementById(stream.getAttribute('target'))
      if (target && target.hasAttribute('data-final')) return
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

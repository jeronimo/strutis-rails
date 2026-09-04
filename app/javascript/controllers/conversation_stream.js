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
  const stream = document.createElement("turbo-stream")
  stream.innerHTML = data
  document.body.append(stream)
  stream.remove()
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

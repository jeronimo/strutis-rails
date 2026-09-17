import "bootstrap"
import "sortablejs"
import "@hotwired/turbo-rails"
import "controllers"

let newFolderPopover = null

document.addEventListener("click", (event) => {
  if (event.target.id === "new-folder-cancel") {
    newFolderPopover?.dispose()
    newFolderPopover = null
    return
  }
  if (event.target.closest(".popover:has(#new-folder-form)")) return
  const trigger = event.target.closest("[data-new-folder-trigger]")
  if (!trigger) return
  event.preventDefault()
  newFolderPopover?.dispose()
  const template = document.querySelector("#new-folder-form-template")
  const form = template.content.querySelector("form").cloneNode(true)
  form.querySelector("#new-folder-parent-id").value = trigger.dataset.parentId || ""
  const anchor = trigger.closest(".folder-row") || trigger.closest(".new-conversation-row") || trigger
  newFolderPopover = window.bootstrap.Popover.getOrCreateInstance(anchor, {
    html: true,
    trigger: "manual",
    container: "body",
    content: form.outerHTML,
    placement: "bottom",
    sanitize: false
  })
  newFolderPopover.show()
})

document.addEventListener("shown.bs.popover", (event) => {
  setTimeout(() => {
    const input = document.querySelector(".popover.show #new-folder-name")
    if (input) input.focus()
  }, 0)
})

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return
  newFolderPopover?.dispose()
  newFolderPopover = null
})

document.addEventListener("turbo:submit-end", (event) => {
  if (event.target.id !== "new-folder-form" || !event.detail.success) return
  event.target.reset()
  newFolderPopover?.dispose()
  newFolderPopover = null
})

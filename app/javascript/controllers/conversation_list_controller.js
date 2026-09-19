import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items"]

  connect() {
    this.initSortables()
  }

  disconnect() {
    this.destroySortables()
  }

  initSortables() {
    this.sortables = this.itemsTargets.map((list) => window.Sortable.create(list, {
      group: "conversation-tree",
      animation: 150,
      handle: ".drag-handle",
      ghostClass: "sortable-ghost",
      fallbackOnBody: true,
      onMove: (event) => !event.dragged.contains(event.to),
      onEnd: (event) => this.handleEnd(event)
    }))
  }

  destroySortables() {
    (this.sortables || []).forEach((sortable) => sortable.destroy())
    this.sortables = []
  }

  handleEnd(event) {
    const item = event.item
    const list = event.to
    const previous = item.previousElementSibling
    const next = item.nextElementSibling
    const parentId = list.dataset.folderId || null
    const payload = {
      parent_id: parentId,
      folder_id: parentId,
      prev_type: previous?.dataset.type,
      prev_id: previous?.dataset.id,
      next_type: next?.dataset.type,
      next_id: next?.dataset.id,
      active_conversation_public_id: this.data.get("activeConversation") || null
    }
    const url = item.dataset.type === "folder" ? `/folders/${item.dataset.id}/move` : `/conversations/${item.dataset.id}/move`
    fetch(url, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        accept: "text/vnd.turbo-stream.html",
        "content-type": "application/json",
        "x-csrf-token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify(payload)
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Move failed: ${response.status}`)
        return response.text()
      })
      .then((html) => Turbo.streamHTML(html))
      .catch(() => window.location.reload())
  }

}

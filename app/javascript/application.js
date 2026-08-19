import "bootstrap"
import "@hotwired/turbo-rails"
import "controllers"

// Custom Turbo Stream action for redirect
Turbo.StreamActions.redirect = function() {
  var url = this.getAttribute('url') || this.textContent.trim();
  Turbo.visit(url);
}

// Handle 401 responses from login form - redirect to home
document.addEventListener("turbo:before-fetch-response", (event) => {
  const form = event.target.closest("form#auth-form")
  if (form) {
    const { fetchOptions, fetchResponse } = event.detail
    const { response } = fetchResponse
    if (response && response.status === 401) {
      event.preventDefault()
      Turbo.visit("/")
    }
  }
})

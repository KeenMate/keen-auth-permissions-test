// AuthEvents hook — handles hard-block push events from LiveView
const AuthEvents = {
  mounted() {
    this.handleEvent("auth:hard_block", ({ message, clear_url }) => {
      // 1. Create full-screen blocking overlay
      const overlay = document.createElement("div")
      overlay.id = "auth-hard-block-overlay"
      overlay.style.cssText =
        "position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.7);"

      overlay.innerHTML = `
        <div class="card bg-base-100 shadow-2xl w-96">
          <div class="card-body items-center text-center">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-16 w-16 text-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <h2 class="card-title text-error mt-2">Access Revoked</h2>
            <p class="py-2">${message}</p>
            <span class="loading loading-spinner loading-md mt-2"></span>
            <p class="text-sm text-base-content/50 mt-1">Redirecting to login...</p>
          </div>
        </div>
      `

      document.body.appendChild(overlay)

      // 2. POST to /auth/clear to invalidate session
      const csrfToken = document
        .querySelector("meta[name='csrf-token']")
        ?.getAttribute("content")

      fetch(clear_url, {
        method: "POST",
        headers: {
          "x-csrf-token": csrfToken || "",
        },
      }).catch(() => {
        // Session clear failed — still redirect
      })

      // 3. Disconnect LiveView websocket
      if (window.liveSocket) {
        window.liveSocket.disconnect()
      }

      // 4. After 2s delay redirect to login
      setTimeout(() => {
        window.location.href = "/login"
      }, 2000)
    })
  },
}

export default AuthEvents

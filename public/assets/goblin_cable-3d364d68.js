// Stands in for the browser's WebSocket on Campfire's /cable URL.
//
// goblin-host runs one short-lived process per request and cannot hold a
// WebSocket open, so this shim gives @rails/actioncable the socket it expects
// and carries the ActionCable protocol over JSON POSTs to /cable instead:
// subscribe, unsubscribe and perform become one request each, and broadcasts
// arrive through a long poll. The server side is lib/controllers/cable.gbln.
//
// The shim answers the parts of the protocol that need no server round trip
// itself: the welcome message after connecting and the pings that keep
// ActionCable's ConnectionMonitor from reconnecting.
(function () {
  const NativeWebSocket = window.WebSocket
  const PING_INTERVAL = 3000
  const RETRY_DELAY = 2000

  class GoblinCable {
    // ActionCable reads the socket's state by enumerating these.
    static CONNECTING = 0
    static OPEN = 1
    static CLOSING = 2
    static CLOSED = 3

    constructor(url, protocols) {
      const location = new URL(url, window.location.href)
      if (!/\/cable\/?$/.test(location.pathname)) return new NativeWebSocket(url, protocols)

      this.url = url
      this.endpoint = window.location.origin + location.pathname.replace(/\/$/, "")
      this.protocol = ""
      this.readyState = GoblinCable.CONNECTING
      this.extensions = ""
      this.binaryType = "blob"
      this.bufferedAmount = 0
      this.onopen = this.onmessage = this.onclose = this.onerror = null

      this.listeners = {}
      this.subscriptions = new Map() // identifier -> broadcast id it has seen up to
      this.queue = Promise.resolve()
      this.pollController = null

      this.#connect()
    }

    addEventListener(type, listener) {
      (this.listeners[type] ||= []).push(listener)
    }

    removeEventListener(type, listener) {
      this.listeners[type] = (this.listeners[type] || []).filter(l => l !== listener)
    }

    dispatchEvent(event) {
      const handler = this["on" + event.type]
      if (handler) handler.call(this, event)
      for (const listener of this.listeners[event.type] || []) listener.call(this, event)
      return true
    }

    send(data) {
      if (this.readyState !== GoblinCable.OPEN) throw new DOMException("WebSocket is not open", "InvalidStateError")
      const { command, identifier, data: payload } = JSON.parse(data)
      // Commands run in order, as they would on a socket.
      this.queue = this.queue.then(() => this.#command(command, identifier, payload)).catch(() => {})
    }

    close(code = 1000, reason = "") {
      if (this.readyState >= GoblinCable.CLOSING) return
      this.readyState = GoblinCable.CLOSING
      for (const identifier of this.subscriptions.keys()) {
        this.#post({ command: "unsubscribe", identifier }, { keepalive: true }).catch(() => {})
      }
      this.#closed(code, reason, true)
    }

    // Private

    async #connect() {
      try {
        const response = await this.#post({ command: "connect" })
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        this.cursor = (await response.json()).cursor
      } catch (error) {
        this.dispatchEvent(new Event("error"))
        this.#closed(1006, "", false)
        return
      }
      this.readyState = GoblinCable.OPEN
      this.protocol = "actioncable-v1-json"
      this.dispatchEvent(new Event("open"))
      this.#receive({ type: "welcome" })
      this.pingTimer = setInterval(() => this.#receive({ type: "ping", message: Math.round(Date.now() / 1000) }), PING_INTERVAL)
      window.addEventListener("pagehide", this.pagehide = () => this.close())
      this.#poll()
    }

    async #command(command, identifier, data) {
      if (command === "subscribe") {
        const reply = await this.#request({ command, identifier })
        if (reply.type === "confirm_subscription") {
          this.subscriptions.set(identifier, Math.max(reply.since || 0, this.cursor || 0))
          this.#restartPoll()
        }
        this.#receive({ identifier, type: reply.type })
      } else if (command === "unsubscribe") {
        this.subscriptions.delete(identifier)
        this.#restartPoll()
        await this.#request({ command, identifier })
      } else if (command === "message") {
        await this.#request({ command, identifier, data })
      }
    }

    async #request(body) {
      const response = await this.#post(body)
      if (response.status === 401) {
        this.#receive({ type: "disconnect", reason: "unauthorized", reconnect: false })
        this.close()
        throw new Error("unauthorized")
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return response.json()
    }

    #post(body, options = {}) {
      return fetch(this.endpoint, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify(body),
        ...options
      })
    }

    async #poll() {
      while (this.readyState === GoblinCable.OPEN) {
        if (this.subscriptions.size === 0) {
          await this.#wait()
          continue
        }

        const controller = this.pollController = new AbortController()
        const subscriptions = [ ...this.subscriptions ].map(([ identifier, since ]) => ({ identifier, since }))
        try {
          const response = await this.#post({ command: "poll", subscriptions }, { signal: controller.signal })
          if (response.status === 401) {
            this.#receive({ type: "disconnect", reason: "unauthorized", reconnect: false })
            this.close()
            return
          }
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          const { messages, rejected } = await response.json()

          for (const { identifier, id, message } of messages) {
            if (!this.subscriptions.has(identifier)) continue
            if (id <= this.subscriptions.get(identifier)) continue
            this.subscriptions.set(identifier, id)
            this.#receive({ identifier, message })
          }

          // A subscription that no longer passes authorization (a revoked
          // membership, say) is dropped, as a disconnect and a rejected
          // resubscribe would drop it on a socket.
          for (const identifier of rejected) {
            this.subscriptions.delete(identifier)
            this.#receive({ identifier, type: "reject_subscription" })
          }
        } catch (error) {
          if (controller.signal.aborted) continue
          await this.#wait(RETRY_DELAY)
        }
      }
    }

    #restartPoll() {
      if (this.pollController) this.pollController.abort()
      if (this.wake) this.wake()
    }

    #wait(ms) {
      return new Promise(resolve => {
        const done = () => { clearTimeout(timer); this.wake = null; resolve() }
        const timer = ms ? setTimeout(done, ms) : null
        this.wake = done
      })
    }

    #receive(message) {
      if (this.readyState !== GoblinCable.OPEN) return
      this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(message) }))
    }

    #closed(code, reason, wasClean) {
      clearInterval(this.pingTimer)
      if (this.pagehide) window.removeEventListener("pagehide", this.pagehide)
      if (this.pollController) this.pollController.abort()
      if (this.wake) this.wake()
      this.readyState = GoblinCable.CLOSED
      this.subscriptions.clear()
      const event = new Event("close")
      Object.assign(event, { code, reason, wasClean })
      this.dispatchEvent(event)
    }
  }

  window.WebSocket = GoblinCable
})()

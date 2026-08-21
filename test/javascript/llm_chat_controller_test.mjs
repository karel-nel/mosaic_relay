import test from "node:test"
import assert from "node:assert/strict"
import LlmChatController from "../../app/javascript/controllers/llm_chat_controller.js"

function citationController() {
  return {
    domainFor: LlmChatController.prototype.domainFor,
    safeImageUrl: LlmChatController.prototype.safeImageUrl,
    safeSourceUrl: LlmChatController.prototype.safeSourceUrl
  }
}

test("subscribes to the namespaced engine channel", () => {
  assert.equal(LlmChatController.channelName, "MosaicRelay::RelayChatChannel")
})

test("citation view model uses a guarded image thumbnail while retaining the canonical source URL", () => {
  const source = LlmChatController.prototype.citationViewModel.call(citationController(), {
    title: "Race day information",
    url: "https://mosaic.example/race-day",
    content_type: "page",
    page_number: 4,
    asset: {
      kind: "image",
      thumbnail_url: "https://cdn.example.com/race-day-thumb.jpg",
      url: "https://cdn.example.com/race-day.jpg",
      alt_text: "Runners at the start line",
      caption: "Race day 2026"
    }
  })

  assert.equal(source.href, "https://mosaic.example/race-day")
  assert.equal(source.thumbnailUrl, "https://cdn.example.com/race-day-thumb.jpg")
  assert.equal(source.thumbnailAlt, "Runners at the start line")
  assert.equal(source.secondaryLabel, "Race day 2026")
  assert.equal(source.detail, "mosaic.example · page · Page 4")
})

test("citation view model falls back to a safe original image URL and rejects unsafe image protocols", () => {
  const controller = citationController()
  const original = LlmChatController.prototype.citationViewModel.call(controller, {
    title: "Source",
    url: "https://mosaic.example/source",
    asset: { kind: "image", url: "https://cdn.example.com/original.jpg" }
  })
  const unsafe = LlmChatController.prototype.citationViewModel.call(controller, {
    title: "Source",
    url: "https://mosaic.example/source",
    asset: { kind: "image", thumbnail_url: "javascript:alert(1)", url: "http://cdn.example.com/original.jpg" }
  })

  assert.equal(original.thumbnailUrl, "https://cdn.example.com/original.jpg")
  assert.equal(unsafe.thumbnailUrl, null)
})

test("citation view model supports the guarded legacy image URL while Relay citations migrate to assets", () => {
  const source = LlmChatController.prototype.citationViewModel.call(citationController(), {
    title: "Legacy source",
    url: "https://mosaic.example/source",
    image_url: "https://cdn.example.com/source.jpg"
  })

  assert.equal(source.href, "https://mosaic.example/source")
  assert.equal(source.thumbnailUrl, "https://cdn.example.com/source.jpg")
})

test("uploaded source view model exposes image and PDF assets as safe inline links", () => {
  const controller = citationController()
  const image = LlmChatController.prototype.uploadedSourceViewModel.call(controller, {
    title: "Uploaded Elevation",
    url: "https://relay.example/uploads/elevation.jpeg",
    asset: {
      kind: "image",
      thumbnail_url: "https://relay.example/uploads/elevation-thumb.jpeg",
      alt_text: "Elevation map"
    }
  })
  const pdf = LlmChatController.prototype.uploadedSourceViewModel.call(controller, {
    title: "Safety manual",
    url: "https://relay.example/uploads/safety.pdf",
    asset: { kind: "pdf", page_count: 24 }
  })

  assert.equal(image.href, "https://relay.example/uploads/elevation.jpeg")
  assert.equal(image.thumbnailUrl, "https://relay.example/uploads/elevation-thumb.jpeg")
  assert.equal(image.thumbnailAlt, "Elevation map")
  assert.equal(image.isImage, true)
  assert.equal(pdf.href, "https://relay.example/uploads/safety.pdf")
  assert.equal(pdf.isPdf, true)
  assert.equal(pdf.pageCount, 24)
})

test("assistant answers omit redundant Markdown links for rendered uploaded sources", () => {
  const sourceUrl = "http://niimble.ngrok.app/rails/active_storage/blobs/redirect/elevation.jpeg"
  const answer = [
    "The elevation profile ranges from about 150 meters to 875 meters.",
    "",
    `[Uploaded source](${sourceUrl})`,
    `[**Uploaded Elevation**](${sourceUrl})**`
  ].join("\n")

  const result = LlmChatController.prototype.answerWithoutUploadedSourceLinks.call({}, answer, [{ url: sourceUrl }])

  assert.equal(result, "The elevation profile ranges from about 150 meters to 875 meters.")
})

test("development accepts HTTP uploaded media while production keeps it blocked", () => {
  const source = {
    title: "Uploaded Elevation",
    url: "http://niimble.ngrok.app/uploads/elevation.jpeg",
    asset: { kind: "image", thumbnail_url: "http://niimble.ngrok.app/uploads/elevation.jpeg" }
  }
  const developmentController = { ...citationController(), allowInsecureAssetsValue: true }

  const development = LlmChatController.prototype.uploadedSourceViewModel.call(developmentController, source)
  const production = LlmChatController.prototype.uploadedSourceViewModel.call(citationController(), source)

  assert.equal(development.href, "http://niimble.ngrok.app/uploads/elevation.jpeg")
  assert.equal(development.thumbnailUrl, "http://niimble.ngrok.app/uploads/elevation.jpeg")
  assert.equal(production.href, null)
  assert.equal(production.thumbnailUrl, null)
})

test("citation view model gives PDF sources page and document context without a thumbnail", () => {
  const source = LlmChatController.prototype.citationViewModel.call(citationController(), {
    title: "Safety manual 2026",
    url: "https://mosaic.example/documents/safety-manual-2026.pdf",
    content_type: "pdf",
    page_number: 4,
    asset: { kind: "pdf", page_count: 24, caption: "Safety manual 2026" }
  })

  assert.equal(source.isPdf, true)
  assert.equal(source.thumbnailUrl, null)
  assert.equal(source.detail, "mosaic.example · pdf · Page 4 · 24 pages")
})

test("chat textarea grows with content and caps its height", () => {
  const classes = new Set()
  const input = {
    tagName: "TEXTAREA",
    scrollHeight: 220,
    style: {},
    classList: { toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name) } }
  }

  LlmChatController.prototype.resizeInput.call({}, input)

  assert.equal(input.style.height, "160px")
  assert.equal(classes.has("overflow-y-auto"), true)
  assert.equal(classes.has("overflow-y-hidden"), false)
})

test("Enter submits a chat textarea while Shift+Enter preserves a new line", () => {
  let submitted = 0
  let prevented = 0
  const target = { form: { requestSubmit() { submitted += 1 } } }

  LlmChatController.prototype.submitOnEnter.call({}, { key: "Enter", target, preventDefault() { prevented += 1 } })
  LlmChatController.prototype.submitOnEnter.call({}, { key: "Enter", shiftKey: true, target, preventDefault() { prevented += 1 } })

  assert.equal(submitted, 1)
  assert.equal(prevented, 1)
})

test("a restored conversation starts in the initial chat view after refresh", () => {
  let showedConversation = false
  let subscribed = false
  let checkedAvailability = false
  const controller = {
    restoreConversationId() { return "existing-conversation" },
    restoreVisitorId() { return "visitor-123" },
    subscribeToAvailability() { subscribed = true },
    checkAvailability() { checkedAvailability = true },
    showConversation() { showedConversation = true }
  }

  LlmChatController.prototype.connect.call(controller)

  assert.equal(controller.conversationId, "existing-conversation")
  assert.equal(controller.visitorId, "visitor-123")
  assert.equal(showedConversation, false)
  assert.equal(subscribed, true)
  assert.equal(checkedAvailability, true)
})

test("availability failure hides a new chat without showing an error", async () => {
  const originalFetch = global.fetch
  global.fetch = async () => ({ ok: true, json: async () => ({ available: false }) })

  let hidden = false
  const controller = {
    availabilityUrlValue: "/api/relay/chat/availability",
    conversationId: null,
    hideForAvailability() { hidden = true }
  }

  assert.equal(await LlmChatController.prototype.checkAvailability.call(controller), false)
  assert.equal(hidden, true)
  global.fetch = originalFetch
})

test("availability failure keeps an existing Relay conversation visible", async () => {
  const originalFetch = global.fetch
  global.fetch = async () => ({ ok: true, json: async () => ({ available: false }) })

  let hidden = false
  const controller = {
    availabilityUrlValue: "/api/relay/chat/availability",
    conversationId: "existing-conversation",
    hideForAvailability() { hidden = true }
  }

  assert.equal(await LlmChatController.prototype.checkAvailability.call(controller), false)
  assert.equal(hidden, false)
  global.fetch = originalFetch
})

test("availability success reveals the chat after its silent bootstrap check", async () => {
  const originalFetch = global.fetch
  global.fetch = async () => ({ ok: true, json: async () => ({ available: true }) })

  let revealed = false
  const controller = {
    availabilityUrlValue: "/api/relay/chat/availability",
    conversationId: null,
    element: { classList: { remove(name) { revealed = name === "hidden" } } }
  }

  assert.equal(await LlmChatController.prototype.checkAvailability.call(controller), true)
  assert.equal(revealed, true)
  global.fetch = originalFetch
})

test("a realtime unavailable event only hides a chat without a conversation", () => {
  let hidden = false
  LlmChatController.prototype.handleChatUnavailable.call({ conversationId: null, hideForAvailability() { hidden = true } })
  assert.equal(hidden, true)

  hidden = false
  LlmChatController.prototype.handleChatUnavailable.call({ conversationId: "existing-conversation", hideForAvailability() { hidden = true } })
  assert.equal(hidden, false)
})

test("reset discards the saved conversation before hiding an unavailable chat", async () => {
  let cleared = false
  let showedInitial = false
  const controller = {
    requestSequence: 0,
    transitionSequence: 0,
    clearConversationId() { cleared = true },
    messagesTarget: { replaceChildren() {} },
    sourcesTarget: { replaceChildren() {} },
    emptySourcesTarget: { classList: { remove() {} } },
    sourceCountTarget: { textContent: "" },
    setLoading() {},
    async checkAvailability() { return false },
    showInitial() { showedInitial = true }
  }

  await LlmChatController.prototype.reset.call(controller)
  assert.equal(cleared, true)
  assert.equal(showedInitial, false)
})

import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Keeps the Niimble Relay experience on the page while Relay answers in the background.
export default class extends Controller {
  static channelName = "MosaicRelay::RelayChatChannel"

  static targets = [
    "initial", "conversation", "form", "input", "messages", "typing",
    "sendButton", "sources", "sourceCount", "emptySources", "resetButton"
  ]

  static values = { url: String, availabilityUrl: String, allowInsecureAssets: Boolean }

  connect() {
    this.conversationId = this.restoreConversationId()
    this.visitorId = this.restoreVisitorId()
    this.requestSequence = 0
    this.transitionSequence = 0

    // Conversation history is not rendered after a page load, so always begin
    // at the welcome view instead of showing an empty conversation panel.
    this.subscribeToAvailability()
    this.checkAvailability()
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  async submit(event) {
    event.preventDefault()

    const form = event.currentTarget
    const input = form.querySelector("[data-llm-chat-target='input']")
    const message = input.value.trim()
    if (!message || this.isLoading) return

    this.showConversation()
    this.appendMessage("user", message)
    input.value = ""
    this.resizeInput(input)
    this.setLoading(true)
    const requestId = ++this.requestSequence

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({
          conversation_id: this.conversationId,
          message,
          visitor_id: this.visitorId,
          context: {
            current_url: window.location.href,
            locale: document.documentElement.lang || "en-ZA",
            interface: "web",
            interface_type: "web"
          }
        })
      })
      const result = await response.json().catch(() => ({}))

      if (result.chat_unavailable) {
        this.handleChatUnavailable()
        return
      }
      if (!response.ok) throw new Error(result.message || "We could not answer that just now.")

      if (requestId === this.requestSequence) {
        this.conversationId = result.conversation_id || this.conversationId
        this.persistConversationId()
        this.appendMessage(
          "assistant",
          result.answer || "I don't have enough information in the available sources to answer that.",
          result.citations || [],
          result.uploaded_sources || []
        )
        this.renderSources(result.citations || [])
      }
    } catch (error) {
      if (requestId === this.requestSequence) this.appendMessage("assistant", error.message || "We could not answer that just now. Please try again.")
    } finally {
      if (requestId === this.requestSequence) {
        this.setLoading(false)
        this.conversationTarget.querySelector("[data-llm-chat-target='input']")?.focus()
      }
    }
  }

  async reset() {
    this.requestSequence += 1
    this.transitionSequence += 1
    this.clearConversationId()
    this.messagesTarget.replaceChildren()
    this.sourcesTarget.replaceChildren()
    this.emptySourcesTarget.classList.remove("hidden")
    this.sourceCountTarget.textContent = "References appear here"
    this.setLoading(false)
    const available = await this.checkAvailability()
    if (!available) return

    this.showInitial()
  }

  showConversation({ immediate = false } = {}) {
    if (!this.conversationTarget.classList.contains("hidden")) return

    if (immediate) {
      this.initialTarget.classList.add("hidden")
      this.conversationTarget.classList.remove("hidden", "opacity-0", "translate-y-2")
      return
    }

    const transitionId = ++this.transitionSequence
    this.initialTarget.classList.add("opacity-0", "-translate-y-2")
    window.setTimeout(() => {
      if (transitionId !== this.transitionSequence) return
      this.initialTarget.classList.add("hidden")
      this.conversationTarget.classList.remove("hidden")
      requestAnimationFrame(() => this.conversationTarget.classList.remove("opacity-0", "translate-y-2"))
    }, 180)
  }

  showInitial() {
    this.element.classList.remove("hidden")
    this.conversationTarget.classList.add("hidden", "opacity-0", "translate-y-2")
    this.initialTarget.classList.remove("hidden")
    requestAnimationFrame(() => this.initialTarget.classList.remove("opacity-0", "-translate-y-2"))
    this.initialTarget.querySelector("[data-llm-chat-target='input']")?.focus()
  }

  subscribeToAvailability() {
    this.consumer = createConsumer(this.cableUrl())
    this.subscription = this.consumer.subscriptions.create(this.constructor.channelName, {
      connected: () => this.checkAvailability(),
      received: (event) => {
        if (event?.type === "chat_unavailable") this.handleChatUnavailable()
      }
    })
  }

  async checkAvailability() {
    try {
      const response = await fetch(this.availabilityUrlValue, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin",
        cache: "no-store"
      })
      const payload = await response.json().catch(() => ({}))
      const available = response.ok && payload.available === true
      if (available) this.element.classList.remove("hidden")
      else if (!this.conversationId) this.hideForAvailability()
      return available
    } catch {
      if (!this.conversationId) this.hideForAvailability()
      return false
    }
  }

  handleChatUnavailable() {
    if (!this.conversationId) this.hideForAvailability()
  }

  hideForAvailability() {
    this.requestSequence += 1
    this.element.classList.add("hidden")
  }

  cableUrl() {
    const url = new URL("/cable", window.location.href)
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:"
    return url.toString()
  }

  resizeInput(eventOrInput) {
    const input = eventOrInput?.target || eventOrInput
    if (input?.tagName !== "TEXTAREA") return

    input.style.height = "auto"
    const maxHeight = 160
    input.style.height = `${Math.min(input.scrollHeight, maxHeight)}px`
    input.classList.toggle("overflow-y-auto", input.scrollHeight > maxHeight)
    input.classList.toggle("overflow-y-hidden", input.scrollHeight <= maxHeight)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    event.target.form?.requestSubmit()
  }

  appendMessage(role, text, citations = [], uploadedSources = []) {
    const item = document.createElement("article")
    item.className = role === "user" ? "flex justify-end" : "flex flex-col items-start"

    const bubble = document.createElement("div")
    bubble.className = role === "user"
      ? "max-w-[85%] rounded-[1.25rem] rounded-br-md bg-white/10 px-4 py-3 text-sm leading-6 text-neutral-100 sm:max-w-[72%]"
      : "max-w-[92%] whitespace-pre-wrap text-[15px] leading-6 text-neutral-200 sm:max-w-[86%]"
    if (role === "assistant") {
      this.appendUploadedSourceImages(item, uploadedSources)
      this.appendAnswerContent(bubble, this.answerWithoutUploadedSourceLinks(text, uploadedSources), citations)
    } else {
      bubble.textContent = text
    }
    item.append(bubble)

    this.messagesTarget.append(item)
    this.scrollMessagesToBottom()
  }

  appendAnswerContent(element, answer, citations) {
    String(answer).split(/(\[\d+\])/g).forEach((part) => {
      const match = part.match(/^\[(\d+)\]$/)
      const citation = match && citations[Number(match[1]) - 1]

      if (!citation?.url) {
        element.append(document.createTextNode(part))
        return
      }

      const link = document.createElement("a")
      link.href = citation.url
      link.target = "_blank"
      link.rel = "noopener noreferrer"
      link.className = "mx-0.5 inline-flex items-center rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-normal leading-none text-neutral-400 transition hover:bg-white/20 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"
      link.textContent = match[1]
      link.setAttribute("aria-label", `Open source ${match[1]}: ${citation.title || "reference"}`)
      element.append(link)
    })
  }

  appendUploadedSourceImages(message, uploadedSources) {
    const sources = Array.isArray(uploadedSources) ? uploadedSources : []
    if (!sources.length) return

    const images = document.createElement("div")
    images.className = "llm-chat-scrollbar mb-4 flex w-full max-w-[92%] snap-x snap-mandatory gap-3 overflow-x-auto overscroll-x-contain pb-2 sm:max-w-[86%]"
    images.setAttribute("aria-label", "Uploaded source images")

    sources.forEach((source) => {
      const viewModel = this.uploadedSourceViewModel(source)
      if (!viewModel.href || !viewModel.isImage || !viewModel.thumbnailUrl) return

      const link = document.createElement("a")
      link.href = viewModel.href
      link.target = "_blank"
      link.rel = "noopener noreferrer"
      link.className = "block shrink-0 snap-start focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"

      const image = document.createElement("img")
      image.src = viewModel.thumbnailUrl
      image.alt = viewModel.thumbnailAlt
      if (!viewModel.thumbnailAlt) image.setAttribute("aria-hidden", "true")
      image.loading = "lazy"
      image.className = "block max-h-52 max-w-[min(68vw,26rem)] rounded-lg object-contain"
      image.addEventListener("error", () => link.remove(), { once: true })
      link.append(image)
      images.append(link)
    })

    if (images.childElementCount) message.append(images)
  }

  answerWithoutUploadedSourceLinks(answer, uploadedSources) {
    const urls = Array.isArray(uploadedSources)
      ? uploadedSources.map((source) => source?.url).filter((url) => typeof url === "string" && url)
      : []

    return urls.reduce((cleanedAnswer, url) => {
      const escapedUrl = url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      const markdownLink = new RegExp(`(?:\\*{1,2})?\\[[^\\]]*\\]\\(${escapedUrl}\\)(?:\\*{1,2})?`, "g")
      return cleanedAnswer.replace(markdownLink, "")
    }, String(answer)).replace(/\n{3,}/g, "\n\n").trim()
  }

  renderSources(citations) {
    const sourceCitations = Array.isArray(citations) ? citations : []
    this.sourcesTarget.replaceChildren()
    this.emptySourcesTarget.classList.toggle("hidden", sourceCitations.length > 0)
    this.sourceCountTarget.textContent = sourceCitations.length
      ? `${sourceCitations.length} ${sourceCitations.length === 1 ? "reference" : "references"}`
      : "No references returned"

    sourceCitations.forEach((citation, index) => {
      if (index > 0) {
        const divider = document.createElement("hr")
        divider.className = "border-0 border-t border-white/10"
        this.sourcesTarget.append(divider)
      }

      const source = this.citationViewModel(citation)
      const link = document.createElement("a")
      link.href = source.href
      link.target = "_blank"
      link.rel = "noopener noreferrer"
      link.className = "group flex min-w-0 items-center gap-3 rounded-2xl bg-transparent p-3 transition duration-200 hover:bg-white/5 focus:outline-none focus-visible:ring-2 focus-visible:ring-amber-400"

      const copy = document.createElement("span")
      copy.className = "min-w-0 flex-1"
      const detail = document.createElement("span")
      detail.className = "block truncate text-[10px] text-neutral-500"
      detail.textContent = source.detail
      const title = document.createElement("strong")
      title.className = "mt-1 block text-xs font-normal leading-4 text-neutral-100"
      title.textContent = source.title
      copy.append(detail, title)

      if (source.secondaryLabel) {
        const secondaryLabel = document.createElement("span")
        secondaryLabel.className = "mt-1 block truncate text-[10px] leading-4 text-neutral-400"
        secondaryLabel.textContent = source.secondaryLabel
        copy.append(secondaryLabel)
      }

      if (source.thumbnailUrl) {
        const thumbnail = document.createElement("img")
        thumbnail.src = source.thumbnailUrl
        thumbnail.alt = source.thumbnailAlt
        if (!source.thumbnailAlt) thumbnail.setAttribute("aria-hidden", "true")
        thumbnail.loading = "lazy"
        thumbnail.className = "size-14 shrink-0 rounded-xl object-cover opacity-90 transition group-hover:opacity-100"
        thumbnail.addEventListener("error", () => thumbnail.remove(), { once: true })
        link.append(copy, thumbnail)
      } else if (source.isPdf) {
        const pdfBadge = document.createElement("span")
        pdfBadge.className = "grid size-14 shrink-0 place-items-center rounded-xl border border-red-400/20 bg-red-500/10 text-[10px] font-normal tracking-wide text-red-200"
        pdfBadge.textContent = "PDF"
        pdfBadge.setAttribute("aria-label", "PDF document")
        link.append(copy, pdfBadge)
      } else {
        link.append(copy)
      }
      this.sourcesTarget.append(link)
    })
  }

  citationViewModel(citation) {
    const asset = citation?.asset && typeof citation.asset === "object" ? citation.asset : null
    const isImage = asset?.kind === "image"
    const legacyImageUrl = citation?.image_url || citation?.image || citation?.metadata?.image_url || citation?.metadata?.cover_image_url
    const pageNumber = citation?.page_number
    const pageDetail = pageNumber ? `Page ${pageNumber}` : null
    const pageCountDetail = asset?.kind === "pdf" && asset.page_count ? `${asset.page_count} pages` : null
    const detail = [
      this.domainFor(citation?.url),
      citation?.content_type,
      pageDetail,
      pageCountDetail
    ].filter(Boolean).join(" · ")

    return {
      href: citation?.url || "#",
      title: citation?.title || "Source",
      detail: detail || "Source",
      thumbnailUrl: isImage
        ? (this.safeImageUrl(asset.thumbnail_url) || this.safeImageUrl(asset.url))
        : this.safeImageUrl(legacyImageUrl),
      thumbnailAlt: asset?.alt_text || citation?.image_alt || "",
      isPdf: asset?.kind === "pdf",
      secondaryLabel: asset?.caption || asset?.alt_text || null
    }
  }

  uploadedSourceViewModel(source) {
    const asset = source?.asset && typeof source.asset === "object" ? source.asset : {}
    const isImage = asset.kind === "image"

    return {
      href: this.safeSourceUrl(source?.url),
      title: source?.title || "Uploaded source",
      thumbnailUrl: isImage ? (this.safeImageUrl(asset.thumbnail_url) || this.safeImageUrl(asset.url)) : null,
      thumbnailAlt: asset.alt_text || asset.caption || source?.title || "",
      isImage,
      isPdf: asset.kind === "pdf",
      pageCount: asset.page_count || null
    }
  }

  safeImageUrl(value) {
    return this.safeSourceUrl(value)
  }

  safeSourceUrl(value) {
    if (typeof value !== "string" || !value.trim()) return null

    try {
      const url = new URL(value)
      const allowsHttp = this.allowInsecureAssetsValue || (typeof window !== "undefined" && window.location.protocol === "http:")
      return url.protocol === "https:" || (allowsHttp && url.protocol === "http:") ? url.toString() : null
    } catch {
      return null
    }
  }

  setLoading(loading) {
    this.isLoading = loading
    this.sendButtonTargets.forEach((button) => {
      button.disabled = loading
      button.classList.toggle("opacity-60", loading)
      button.classList.toggle("cursor-wait", loading)
    })
    this.typingTarget.classList.toggle("hidden", !loading)
    this.scrollMessagesToBottom()
  }

  scrollMessagesToBottom() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTo({ top: this.messagesTarget.scrollHeight, behavior: "smooth" })
    })
  }

  domainFor(url) {
    try {
      return new URL(url).hostname.replace(/^www\./, "")
    } catch {
      return "Source"
    }
  }

  restoreVisitorId() {
    const key = "niimble-relay-visitor-id"
    try {
      const existing = window.localStorage.getItem(key)
      if (existing) return existing
      const visitorId = window.crypto?.randomUUID?.() || `visitor-${Date.now()}-${Math.random().toString(16).slice(2)}`
      window.localStorage.setItem(key, visitorId)
      return visitorId
    } catch {
      return `visitor-${Date.now()}-${Math.random().toString(16).slice(2)}`
    }
  }

  restoreConversationId() {
    try {
      return window.localStorage.getItem("niimble-relay-conversation-id") || null
    } catch {
      return null
    }
  }

  persistConversationId() {
    if (!this.conversationId) return

    try {
      window.localStorage.setItem("niimble-relay-conversation-id", this.conversationId)
    } catch { /* Storage may be unavailable. */ }
  }

  clearConversationId() {
    this.conversationId = null
    try {
      window.localStorage.removeItem("niimble-relay-conversation-id")
    } catch { /* Storage may be unavailable. */ }
  }
}

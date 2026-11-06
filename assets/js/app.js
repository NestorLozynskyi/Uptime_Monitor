// Uptime Monitor browser code: LiveView socket, theme switch, dialogs,
// live relative times and the response-time chart (Chart.js).
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/uptime_monitor"
import topbar from "../vendor/topbar"
import {ResponseChart} from "./response_chart"

const root = document.documentElement
const $$ = (sel, ctx = document) => Array.from(ctx.querySelectorAll(sel))

/* ---------- Theme: light | dark | system (default) ---------- */
const THEME_KEY = "um-theme"
const darkQuery = matchMedia("(prefers-color-scheme: dark)")

function applyTheme(pref) {
  if (!["light", "dark", "system"].includes(pref)) pref = "system"
  // Suppress transitions during the swap so every component lands on the new palette at once.
  root.classList.add("theme-switching")
  root.dataset.themePref = pref
  root.dataset.theme = pref === "system" ? (darkQuery.matches ? "dark" : "light") : pref
  syncThemeButtons()
  void getComputedStyle(document.body).backgroundColor
  setTimeout(() => root.classList.remove("theme-switching"), 0)
  document.dispatchEvent(new CustomEvent("um:theme"))
}

function syncThemeButtons() {
  const pref = root.dataset.themePref || "system"
  $$("[data-theme-set]").forEach(b => b.setAttribute("aria-pressed", String(b.dataset.themeSet === pref)))
}

function setTheme(pref) {
  try { localStorage.setItem(THEME_KEY, pref) } catch (_e) { /* storage unavailable */ }
  applyTheme(pref)
}

document.addEventListener("click", e => {
  const target = e.target instanceof Element ? e.target : e.target.parentElement
  const button = target && target.closest("[data-theme-set]")
  if (button) setTheme(button.dataset.themeSet)
})
darkQuery.addEventListener("change", () => { if (root.dataset.themePref === "system") applyTheme("system") })
window.addEventListener("storage", e => { if (e.key === THEME_KEY) applyTheme(e.newValue || "system") })

/* ---------- Dialogs: menu sheet (client only) ---------- */
document.addEventListener("click", e => {
  const target = e.target instanceof Element ? e.target : null
  if (!target) return
  const opener = target.closest("[data-dialog-open]")
  if (opener) {
    const dialog = document.getElementById(opener.dataset.dialogOpen)
    if (dialog && !dialog.open) {
      dialog.showModal()
      opener.setAttribute("aria-expanded", "true")
      dialog.addEventListener("close", () => { opener.setAttribute("aria-expanded", "false"); opener.focus() }, {once: true})
    }
    return
  }
  const closer = target.closest("[data-dialog-close]")
  if (closer) { closer.closest("dialog")?.close(); return }
  if (target instanceof HTMLDialogElement && target.open) target.close() // backdrop click
})
// Navigating from the sheet closes it.
window.addEventListener("phx:page-loading-start", () => $$("dialog.sheet[open]").forEach(d => d.close()))

/* ---------- Relative times and running durations ---------- */
function fmtAgo(s) {
  if (s < 5) return "just now"
  if (s < 60) return `${s} s ago`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m} min ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h} h ago`
  return `${Math.floor(h / 24)} d ago`
}
function fmtDuration(s) {
  const m = Math.floor(Math.max(s, 0) / 60)
  if (m < 60) return `${m} min`
  if (m < 1440) return `${Math.floor(m / 60)} h ${m % 60} min`
  return `${Math.floor(m / 1440)} d ${Math.floor((m % 1440) / 60)} h`
}
function tick() {
  const now = Date.now()
  $$("time[data-ago]").forEach(n => {
    const t = Date.parse(n.getAttribute("datetime"))
    if (!isNaN(t)) { const text = fmtAgo(Math.max(0, Math.floor((now - t) / 1000))); if (n.textContent !== text) n.textContent = text }
  })
  $$("[data-since]").forEach(n => {
    const t = Date.parse(n.dataset.since)
    if (!isNaN(t)) { const text = fmtDuration(Math.floor((now - t) / 1000)); if (n.textContent !== text) n.textContent = text }
  })
}
setInterval(tick, 1000)

/* ---------- LiveView hooks ---------- */
const Modal = {
  // Server-rendered confirmation dialog (rendered with phx-update="ignore",
  // so patches keep it open): shown as a modal on mount; closing it with
  // Escape or a backdrop click tells the server.
  mounted() {
    this.el.addEventListener("close", () => { if (this.el.isConnected) this.pushEvent(this.el.dataset.onClose, {}) })
    if (!this.el.open) this.el.showModal()
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken, tz_offset: -new Date().getTimezoneOffset() * 60},
  hooks: {...colocatedHooks, ResponseChart, Modal},
})

const accent = getComputedStyle(root).getPropertyValue("--accent").trim() || "#1D4ED8"
topbar.config({barColors: {0: accent}, shadowColor: "rgba(0, 0, 0, .2)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => { topbar.hide(); syncThemeButtons(); tick() })

/* ---------- Radio groups (period switch): arrow keys move the selection ---------- */
document.addEventListener("keydown", e => {
  if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return
  const group = e.target instanceof Element && e.target.closest("[data-period-group]")
  if (!group) return
  const buttons = $$("[role=radio]", group)
  const i = buttons.findIndex(b => b.getAttribute("aria-checked") === "true")
  const next = buttons[(i + (e.key === "ArrowRight" ? 1 : buttons.length - 1)) % buttons.length]
  e.preventDefault()
  next.click()
  next.focus()
})

/* ---------- Highlight a row updated by a live event ---------- */
window.addEventListener("phx:um:updated", e => {
  const el = document.getElementById(e.detail.id)
  if (!el) return
  el.classList.remove("is-updated"); void el.offsetWidth; el.classList.add("is-updated")
  setTimeout(() => el.classList.remove("is-updated"), 1300)
})

/* ---------- Sign-in busy state ---------- */
document.addEventListener("submit", e => {
  const form = e.target
  if (form instanceof HTMLFormElement && form.matches("[data-login-form]")) {
    const btn = form.querySelector("[type=submit]")
    btn?.setAttribute("aria-busy", "true")
  }
})

syncThemeButtons()
tick()
liveSocket.connect()
window.liveSocket = liveSocket

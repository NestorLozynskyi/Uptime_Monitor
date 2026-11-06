// Response-time chart (Chart.js) for the service details page.
//
// One point per slot (average response time of successful checks); the line
// is broken where a slot has no successful checks (spanGaps: false). Slots
// overlapping an incident are drawn as hatched "Down" bands. Colors come from
// the design CSS variables and are re-read when the theme changes.
import Chart from "../vendor/chart.umd.min.js"

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const pad = n => String(n).padStart(2, "0")
const fmtDay = d => `${MONTHS[d.getMonth()]} ${d.getDate()}`
const fmtHM = d => `${pad(d.getHours())}:${pad(d.getMinutes())}`
const fmtDur = s => {
  const m = Math.floor(s / 60)
  if (m < 60) return `${m} min`
  if (m < 1440) return `${Math.floor(m / 60)} h ${m % 60} min`
  return `${Math.floor(m / 1440)} d ${Math.floor((m % 1440) / 60)} h`
}
const fmtMs = v => `${Math.round(v).toLocaleString("en-US")} ms`
// Round axis steps: 1, 2, 2.5 or 5 × 10^n, at most 5 intervals above the data
// (with 15 % headroom), never below 0–500 ms.
export function niceScale(maxValue) {
  const needed = Math.max(500, maxValue * 1.15)
  const raw = needed / 5
  const pow = Math.pow(10, Math.floor(Math.log10(raw)))
  const step = [1, 2, 2.5, 5, 10].map(m => m * pow).find(v => v >= raw - 1e-9)
  return {step, max: Math.ceil(needed / step - 1e-9) * step}
}

const css = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

function colors() {
  return {
    line: css("--chart-line"), area: css("--chart-area"), grid: css("--chart-grid"),
    tick: css("--text-subtle"), down: css("--down-fill"), surface: css("--surface"),
    guide: css("--text-subtle"), mono: css("--font-mono"),
  }
}

function hatchPattern(ctx, color) {
  const c = document.createElement("canvas")
  const size = 6 * (window.devicePixelRatio || 1)
  c.width = c.height = size
  const x = c.getContext("2d")
  x.strokeStyle = color
  x.lineWidth = size * 0.42
  x.beginPath()
  for (let k = -1; k <= 1; k++) { x.moveTo(k * size, size); x.lineTo(k * size + size, 0) }
  x.stroke()
  const pattern = ctx.createPattern(c, "repeat")
  if (pattern.setTransform && window.DOMMatrix) pattern.setTransform(new DOMMatrix().scale(1 / (window.devicePixelRatio || 1)))
  return pattern
}

// Hatched downtime bands + hover guide line and dot.
const overlay = {
  id: "umOverlay",
  beforeDatasetsDraw(chart) {
    const {ctx, chartArea: area, scales: {x}} = chart
    const points = chart.$points || []
    if (!points.length) return
    const step = area.width / points.length
    ctx.save()
    ctx.globalAlpha = 0.28
    ctx.fillStyle = hatchPattern(ctx, chart.$colors.down)
    points.forEach((p, i) => {
      if (p.st === "down") ctx.fillRect(area.left + step * i, area.top, Math.max(step, 3), area.bottom - area.top)
    })
    ctx.restore()
    void x
  },
  afterDatasetsDraw(chart) {
    const i = chart.$hover
    if (i == null) return
    const {ctx, chartArea: area, scales: {x, y}} = chart
    const px = x.getPixelForValue(i)
    ctx.save()
    ctx.strokeStyle = chart.$colors.guide
    ctx.lineWidth = 1
    ctx.setLineDash([3, 3])
    ctx.beginPath(); ctx.moveTo(px, area.top); ctx.lineTo(px, area.bottom); ctx.stroke()
    const v = chart.$points[i]?.ms
    if (v != null) {
      ctx.setLineDash([])
      ctx.fillStyle = chart.$colors.surface
      ctx.strokeStyle = chart.$colors.line
      ctx.lineWidth = 2
      ctx.beginPath(); ctx.arc(px, y.getPixelForValue(v), 4, 0, Math.PI * 2); ctx.fill(); ctx.stroke()
    }
    ctx.restore()
  },
}

export const ResponseChart = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.tip = this.el.querySelector("[data-chart-tip]")
    this.onTheme = () => this.render()
    document.addEventListener("um:theme", this.onTheme)
    this.canvas.addEventListener("pointermove", e => this.hover(e))
    this.canvas.addEventListener("pointerleave", () => this.hover(null))
    this.render()
  },
  updated() { this.render() },
  destroyed() {
    document.removeEventListener("um:theme", this.onTheme)
    this.chart?.destroy()
  },

  read() {
    this.points = JSON.parse(this.el.dataset.points || "[]")
    this.period = this.el.dataset.period
    this.canvas.setAttribute("aria-label", this.el.dataset.label || "Response time")
  },

  label(p) {
    const d = new Date(p.s)
    return this.period === "24h" ? fmtHM(d) : fmtDay(d)
  },

  range(p) {
    const a = new Date(p.s), b = new Date(p.e)
    return this.period === "30d" ? fmtDay(a) : `${fmtDay(a)}, ${fmtHM(a)}–${fmtHM(b)}`
  },

  render() {
    this.read()
    const c = colors()
    const values = this.points.map(p => p.ms).filter(v => v != null)
    const {step, max: vmax} = niceScale(Math.max(0, ...values))
    const narrow = this.el.clientWidth < 480
    const font = {family: c.mono, size: 12}
    const data = {
      labels: this.points.map(p => this.label(p)),
      datasets: [{
        data: this.points.map(p => p.ms),
        borderColor: c.line, backgroundColor: c.area, fill: "origin",
        borderWidth: 2, borderJoinStyle: "round", borderCapStyle: "round",
        pointRadius: 0, pointHoverRadius: 0, tension: 0, spanGaps: false,
      }],
    }
    const options = {
      responsive: true, maintainAspectRatio: false, animation: false,
      events: [],
      layout: {padding: {top: 8, right: 8}},
      plugins: {legend: {display: false}, tooltip: {enabled: false}},
      scales: {
        x: {
          offset: true,
          grid: {display: false}, border: {display: false},
          ticks: {color: c.tick, font, maxRotation: 0, autoSkip: true, maxTicksLimit: narrow ? 3 : 6},
        },
        y: {
          min: 0, max: vmax,
          grid: {color: c.grid, drawTicks: false}, border: {display: false},
          ticks: {color: c.tick, font, padding: 8, stepSize: step, callback: v => fmtMs(v)},
        },
      },
    }
    if (this.chart) {
      this.chart.data = data
      this.chart.options = options
    } else {
      this.chart = new Chart(this.canvas, {type: "line", data, options, plugins: [overlay]})
    }
    this.chart.$points = this.points
    this.chart.$colors = c
    this.chart.$hover = null
    this.tip.hidden = true
    this.chart.update("none")
    // Rendered axis values, for tests and debugging.
    this.canvas.dataset.yTicks = JSON.stringify(this.chart.scales.y.ticks.map(t => t.value))
  },

  hover(e) {
    const chart = this.chart
    if (!chart) return
    const area = chart.chartArea
    let i = null
    if (e) {
      const rect = this.canvas.getBoundingClientRect()
      const x = e.clientX - rect.left
      if (x >= area.left && x <= area.right) {
        i = Math.min(this.points.length - 1, Math.max(0, Math.floor((x - area.left) / (area.width / this.points.length))))
      }
    }
    if (chart.$hover !== i) { chart.$hover = i; chart.draw() }
    if (i == null) { this.tip.hidden = true; return }
    const p = this.points[i]
    let value
    if (p.st === "down") value = `Down · ${fmtDur(p.down)}`
    else if (p.ms != null) value = `Avg ${fmtMs(p.ms)}`
    else value = "No data"
    this.tip.innerHTML = ""
    for (const text of [this.range(p), value]) {
      const span = document.createElement("span")
      span.textContent = text
      this.tip.appendChild(span)
    }
    const px = chart.scales.x.getPixelForValue(i)
    const w = this.el.clientWidth
    this.tip.style.left = `${Math.min(Math.max(px, 80), w - 80)}px`
    this.tip.hidden = false
  },
}

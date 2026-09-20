defmodule Thunk.Dashboard.Page do
  @moduledoc """
  The dashboard page: plain HTML with inline CSS and JavaScript, served
  from memory. The script asks /stats.json for a new snapshot every
  500 ms and redraws the node cards and their charts in place.
  """

  @html ~S"""
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Thunk cluster</title>
  <style>
  :root {
    --bg: #f5f5f3;
    --card: #ffffff;
    --ink: #1c1c1a;
    --muted: #6b6b66;
    --line: #e2e2de;
    --track: #ececea;
    --accent: #2563c9;
    --accent-soft: rgba(37, 99, 201, 0.12);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #151515;
      --card: #1e1e1e;
      --ink: #ececea;
      --muted: #9a9a94;
      --line: #313131;
      --track: #2c2c2c;
      --accent: #6f9ef5;
      --accent-soft: rgba(111, 158, 245, 0.16);
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--ink);
    font: 14px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  main { max-width: 1200px; margin: 0 auto; padding: 24px 16px 40px; }
  header { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 24px; margin-bottom: 20px; }
  h1 { font-size: 22px; font-weight: 600; margin: 0; }
  #status { color: var(--muted); }
  #status.error { color: var(--ink); font-weight: 600; }
  .summary { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }
  .tile { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 10px 14px; min-width: 150px; }
  .tile .value { font-size: 22px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .label { color: var(--muted); font-size: 12px; }
  #nodes { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(280px, 100%), 1fr)); gap: 16px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; }
  .card.down { opacity: 0.45; }
  .card.down .fill { background: var(--muted); }
  .card.down svg .line { stroke: var(--muted); }
  .top { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .name { font-weight: 600; overflow-wrap: anywhere; }
  .state { font-size: 12px; color: var(--muted); border: 1px solid var(--line); border-radius: 10px; padding: 0 8px; white-space: nowrap; }
  .card:not(.down) .state { color: var(--accent); border-color: var(--accent); }
  .row { display: flex; justify-content: space-between; margin-top: 10px; font-variant-numeric: tabular-nums; }
  .bar { height: 8px; background: var(--track); border-radius: 4px; overflow: hidden; margin-top: 4px; }
  .fill { height: 100%; width: 0; background: var(--accent); border-radius: 4px; }
  .totals { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; margin-top: 12px; }
  .totals .value { font-variant-numeric: tabular-nums; font-weight: 600; }
  svg { display: block; width: 100%; height: 64px; margin-top: 12px; }
  svg .grid { stroke: var(--line); stroke-width: 1; }
  svg .line { fill: none; stroke: var(--accent); stroke-width: 2; stroke-linejoin: round; }
  svg .area { fill: var(--accent-soft); stroke: none; }
  .card.down svg .area { fill: none; }
  .readout { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; margin-top: 4px; }
  </style>
  </head>
  <body>
  <main>
  <header>
    <h1>Thunk cluster</h1>
    <span id="status">connecting</span>
  </header>
  <div class="summary">
    <div class="tile"><div class="label">nodes up</div><div class="value" id="s-up">-</div></div>
    <div class="tile"><div class="label">pieces evaluated per second</div><div class="value" id="s-rate">-</div></div>
    <div class="tile"><div class="label">pieces evaluated</div><div class="value" id="s-evaluated">-</div></div>
    <div class="tile"><div class="label">steals</div><div class="value" id="s-steals">-</div></div>
  </div>
  <div id="nodes"></div>
  </main>
  <template id="card">
    <section class="card">
      <div class="top"><span class="name" data-f="name"></span><span class="state" data-f="state"></span></div>
      <div class="row"><span class="label">evaluators running</span><span data-f="running"></span></div>
      <div class="bar"><div class="fill" data-f="bar"></div></div>
      <div class="row"><span class="label">deque</span><span data-f="queued"></span></div>
      <div class="totals">
        <div><div class="label">steals</div><div class="value" data-f="steals"></div></div>
        <div><div class="label">given</div><div class="value" data-f="stolen_from"></div></div>
        <div><div class="label">evaluated</div><div class="value" data-f="evaluated"></div></div>
        <div><div class="label">recovered</div><div class="value" data-f="recovered"></div></div>
      </div>
      <svg viewBox="0 0 300 64" preserveAspectRatio="none">
        <line class="grid" x1="0" y1="63.5" x2="300" y2="63.5" vector-effect="non-scaling-stroke"></line>
        <line class="grid" x1="0" y1="0.5" x2="300" y2="0.5" vector-effect="non-scaling-stroke"></line>
        <path class="area" data-f="area"></path>
        <path class="line" data-f="line" vector-effect="non-scaling-stroke"></path>
      </svg>
      <div class="readout" data-f="readout"></div>
    </section>
  </template>
  <script>
  const W = 300, H = 64, WINDOW = 120000;
  const cards = new Map();
  let last = null;

  function fmt(n) { return n.toLocaleString("en-US"); }
  function fmtRate(r) { return r < 10 ? r.toFixed(1) : fmt(Math.round(r)); }

  // Upper end of the y axis: 1, 2 or 5 times a power of ten.
  function niceMax(v) {
    if (v <= 1) return 1;
    const p = Math.pow(10, Math.floor(Math.log10(v)));
    for (const m of [1, 2, 5, 10]) if (m * p >= v) return m * p;
  }

  function card(name) {
    if (cards.has(name)) return cards.get(name);
    const node = document.getElementById("card").content.firstElementChild.cloneNode(true);
    const f = {};
    node.querySelectorAll("[data-f]").forEach(e => { f[e.dataset.f] = e; });
    f.name.textContent = name;
    const c = { node, f, name, hover: null };
    node.querySelector("svg").addEventListener("mousemove", ev => {
      const box = ev.currentTarget.getBoundingClientRect();
      c.hover = (ev.clientX - box.left) / box.width;
      if (last) readout(c, last);
    });
    node.querySelector("svg").addEventListener("mouseleave", () => {
      c.hover = null;
      if (last) readout(c, last);
    });
    cards.set(name, c);
    const all = [...cards.keys()].sort();
    const grid = document.getElementById("nodes");
    const next = all[all.indexOf(name) + 1];
    grid.insertBefore(node, next ? cards.get(next).node : null);
    return c;
  }

  function nowRate(snap, name) {
    const s = snap.history[snap.history.length - 1];
    return s && s.rates[name] !== undefined ? s.rates[name] : 0;
  }

  function readout(c, snap) {
    const n = snap.nodes.find(x => x.name === c.name);
    if (c.hover === null) {
      c.f.readout.textContent = n && n.up
        ? fmtRate(nowRate(snap, c.name)) + " pieces/s now, " + fmtRate(n.steal_rate) + " steals/s"
        : "not answering";
      return;
    }
    const t = snap.time - (1 - c.hover) * WINDOW;
    let best = null;
    for (const s of snap.history) if (!best || Math.abs(s.t - t) < Math.abs(best.t - t)) best = s;
    const ago = Math.round((snap.time - (best ? best.t : t)) / 1000);
    const r = best ? best.rates[c.name] : undefined;
    c.f.readout.textContent = ago + " s ago: " + (r === undefined ? "down" : fmtRate(r) + " pieces/s");
  }

  function draw(c, snap, ymax) {
    const segments = [];
    let current = [];
    for (const s of snap.history) {
      const r = s.rates[c.name];
      const x = W - (snap.time - s.t) / WINDOW * W;
      if (x < 0) continue;
      if (r === undefined) {
        if (current.length) segments.push(current);
        current = [];
      } else {
        current.push([x, H - (r / ymax) * (H - 2)]);
      }
    }
    if (current.length) segments.push(current);
    // one subpath per stretch in which the node was up, so down time is a gap
    const xy = p => p[0].toFixed(1) + "," + p[1].toFixed(1);
    c.f.line.setAttribute("d", segments.map(seg => "M" + seg.map(xy).join(" L")).join(" "));
    c.f.area.setAttribute("d", segments.map(seg =>
      "M" + seg[0][0].toFixed(1) + "," + H + " L" + seg.map(xy).join(" L") +
      " L" + seg[seg.length - 1][0].toFixed(1) + "," + H + " Z").join(" "));
  }

  // Pieces are few and large, so the rate of a single interval jumps
  // between zero and a peak. The chart shows the mean of the last
  // SMOOTH samples instead, stopping at a gap.
  const SMOOTH = 4;
  function smooth(history) {
    return history.map((s, i) => {
      const rates = {};
      for (const k in s.rates) {
        let sum = 0, n = 0;
        for (let j = i; j >= 0 && j > i - SMOOTH && history[j].rates[k] !== undefined; j--) {
          sum += history[j].rates[k];
          n++;
        }
        rates[k] = sum / n;
      }
      return { t: s.t, rates };
    });
  }

  function render(raw) {
    const snap = Object.assign({}, raw, { history: smooth(raw.history) });
    last = snap;
    let ymax = 0;
    for (const s of snap.history) for (const k in s.rates) ymax = Math.max(ymax, s.rates[k]);
    ymax = niceMax(ymax);

    let up = 0, rate = 0, evaluated = 0, steals = 0;
    for (const n of snap.nodes) {
      const c = card(n.name);
      c.node.classList.toggle("down", !n.up);
      c.f.state.textContent = n.up ? "up" : "down";
      c.f.running.textContent = n.running + " / " + n.limit;
      c.f.bar.style.width = (n.limit > 0 ? Math.min(100, 100 * n.running / n.limit) : 0) + "%";
      c.f.queued.textContent = fmt(n.queued);
      c.f.steals.textContent = fmt(n.steals);
      c.f.stolen_from.textContent = fmt(n.stolen_from);
      c.f.evaluated.textContent = fmt(n.evaluated);
      c.f.recovered.textContent = fmt(n.recovered);
      draw(c, snap, ymax);
      readout(c, snap);
      if (n.up) { up++; rate += nowRate(snap, n.name); }
      evaluated += n.evaluated;
      steals += n.steals;
    }
    document.getElementById("s-up").textContent = up + " of " + snap.nodes.length;
    document.getElementById("s-rate").textContent = fmtRate(rate);
    document.getElementById("s-evaluated").textContent = fmt(evaluated);
    document.getElementById("s-steals").textContent = fmt(steals);
    const status = document.getElementById("status");
    status.className = "";
    status.textContent = "from " + snap.node + ", chart scale 0 to " + fmt(ymax) +
      " pieces/s, last 2 minutes, mean over " + (SMOOTH * snap.interval / 1000) + " s";
  }

  async function poll() {
    try {
      const res = await fetch("/stats.json", { cache: "no-store" });
      if (!res.ok) throw new Error(res.status);
      render(await res.json());
    } catch (e) {
      const status = document.getElementById("status");
      status.className = "error";
      status.textContent = "the dashboard does not answer";
    }
    setTimeout(poll, 500);
  }
  poll();
  </script>
  </body>
  </html>
  """

  def html, do: @html
end

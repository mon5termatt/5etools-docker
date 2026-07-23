(function () {
  if (window.__5etoolsStatusOverlay) return;
  window.__5etoolsStatusOverlay = true;

  const STYLE = `
    #fivetools-status-overlay {
      position: fixed;
      right: 16px;
      bottom: 16px;
      z-index: 2147483646;
      max-width: min(360px, calc(100vw - 32px));
      font: 13px/1.4 "Segoe UI", "Helvetica Neue", sans-serif;
      color: #e8eaef;
      background: rgba(18, 20, 26, 0.92);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 10px;
      box-shadow: 0 8px 28px rgba(0,0,0,0.35);
      padding: 12px 14px 12px 12px;
      display: none;
      gap: 10px;
      align-items: flex-start;
      backdrop-filter: blur(8px);
    }
    #fivetools-status-overlay[data-visible="1"] { display: flex; }
    #fivetools-status-overlay .spin {
      width: 16px;
      height: 16px;
      margin-top: 2px;
      flex: 0 0 auto;
      border: 2px solid rgba(255,255,255,0.15);
      border-top-color: #3d9cf0;
      border-radius: 50%;
      animation: fivetools-spin 0.75s linear infinite;
    }
    #fivetools-status-overlay .body { min-width: 0; flex: 1; }
    #fivetools-status-overlay .title {
      font-weight: 650;
      letter-spacing: -0.01em;
      margin: 0 0 2px;
    }
    #fivetools-status-overlay .msg,
    #fivetools-status-overlay .detail {
      margin: 0;
      color: #a8b0c2;
      word-break: break-word;
    }
    #fivetools-status-overlay .detail { margin-top: 2px; font-size: 12px; }
    #fivetools-status-overlay .phase {
      margin-top: 6px;
      font-size: 11px;
      color: #3d9cf0;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    #fivetools-status-overlay button {
      appearance: none;
      border: 0;
      background: transparent;
      color: #8b93a7;
      cursor: pointer;
      font-size: 16px;
      line-height: 1;
      padding: 0 0 0 6px;
    }
    #fivetools-status-overlay button:hover { color: #e8eaef; }
    @keyframes fivetools-spin { to { transform: rotate(360deg); } }
  `;

  const style = document.createElement("style");
  style.textContent = STYLE;
  document.documentElement.appendChild(style);

  const el = document.createElement("div");
  el.id = "fivetools-status-overlay";
  el.setAttribute("role", "status");
  el.setAttribute("aria-live", "polite");
  el.innerHTML = `
    <div class="spin" aria-hidden="true"></div>
    <div class="body">
      <p class="title">5etools sync</p>
      <p class="msg"></p>
      <p class="detail"></p>
      <p class="phase"></p>
    </div>
    <button type="button" title="Dismiss" aria-label="Dismiss">×</button>
  `;
  document.documentElement.appendChild(el);

  const msgEl = el.querySelector(".msg");
  const detailEl = el.querySelector(".detail");
  const phaseEl = el.querySelector(".phase");
  let dismissedPhase = null;

  el.querySelector("button").addEventListener("click", () => {
    dismissedPhase = phaseEl.textContent || "dismissed";
    el.dataset.visible = "0";
  });

  function busy(data) {
    if (!data) return true;
    if (typeof data.busy === "boolean") return data.busy;
    return data.phase !== "ready";
  }

  async function tick() {
    try {
      const res = await fetch("/status.json?ts=" + Date.now(), { cache: "no-store" });
      if (!res.ok) throw new Error("status " + res.status);
      const data = await res.json();
      const phase = data.phase || "";
      msgEl.textContent = data.message || "Working…";
      detailEl.textContent = data.detail || "";
      phaseEl.textContent = phase;

      if (busy(data)) {
        if (dismissedPhase !== phase) {
          dismissedPhase = null;
          el.dataset.visible = "1";
        }
      } else {
        el.dataset.visible = "0";
        dismissedPhase = null;
      }
    } catch (_) {
      // Keep last state if status endpoint briefly unavailable
    }
    setTimeout(tick, 2000);
  }

  tick();
})();

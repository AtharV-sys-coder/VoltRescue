const FLOW = [
  "REQUEST_SUBMITTED",
  "PENDING_ASSIGNMENT",
  "COLLECTOR_ASSIGNED",
  "PICKUP_ACCEPTED",
  "COLLECTOR_EN_ROUTE",
  "PICKUP_COMPLETED",
  "IN_COLLECTOR_CUSTODY",
  "TRANSFER_SCHEDULED",
  "IN_TRANSIT_TO_RECYCLER",
  "RECEIVED_BY_RECYCLER",
  "RECYCLER_VALIDATED",
  "PROCESS_COMPLETED",
];

const COLLECTOR_NEXT = {
  COLLECTOR_ASSIGNED: null,
  PICKUP_ACCEPTED: "COLLECTOR_EN_ROUTE",
  COLLECTOR_EN_ROUTE: "PICKUP_COMPLETED",
  PICKUP_COMPLETED: "IN_COLLECTOR_CUSTODY",
};

const FAILURE_STATES = ["CANCELLED", "REJECTED", "NO_SHOW", "TRANSFER_FAILED", "RECYCLER_REJECTED"];

// The database stores machine codes; people should not have to read them.
const STATUS_LABEL = {
  REQUEST_SUBMITTED: "Request submitted",
  PENDING_ASSIGNMENT: "Awaiting assignment",
  COLLECTOR_ASSIGNED: "Collector assigned",
  PICKUP_ACCEPTED: "Pickup accepted",
  COLLECTOR_EN_ROUTE: "Collector en route",
  PICKUP_COMPLETED: "Collected",
  IN_COLLECTOR_CUSTODY: "In collector custody",
  TRANSFER_SCHEDULED: "Transfer scheduled",
  IN_TRANSIT_TO_RECYCLER: "In transit to recycler",
  RECEIVED_BY_RECYCLER: "Received by recycler",
  RECYCLER_VALIDATED: "Materials validated",
  PROCESS_COMPLETED: "Recycling completed",
  CANCELLED: "Cancelled",
  REJECTED: "Rejected",
  NO_SHOW: "No-show",
  TRANSFER_FAILED: "Transfer failed",
  RECYCLER_REJECTED: "Rejected by recycler",
};

const BATTERY_TYPES = [
  "Lead-acid (automotive)",
  "Lithium-ion",
  "Motorcycle / Bajaji",
  "UPS / Inverter",
  "Solar storage",
  "Mixed household",
];

const DEMO_ACCOUNTS = [
  { role: "Citizen", email: "citizen@voltrescue.local" },
  { role: "Collector", email: "collector@voltrescue.local" },
  { role: "Recycler", email: "recycler@voltrescue.local" },
  { role: "Admin", email: "admin@voltrescue.local" },
];

function label(status) {
  return STATUS_LABEL[status] || status;
}

// Everything interpolated into innerHTML must pass through here. Addresses and
// remarks are free text typed by residents and would otherwise execute.
function esc(value) {
  if (value === null || value === undefined) return "";
  return String(value).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]);
}

let token = sessionStorage.getItem("vr_token") || "";
let me = null;
let view = "home";
let map, marker;

const app = document.getElementById("app");

function toast(msg) {
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

async function api(path, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  if (token) headers.Authorization = "Bearer " + token;
  if (opts.body && !(opts.body instanceof FormData) && !headers["Content-Type"]) {
    headers["Content-Type"] = "application/json";
  }
  let res;
  try {
    res = await fetch("/api" + path, { ...opts, headers });
  } catch {
    const offline = new Error("Cannot reach the server. Check that it is still running.");
    offline.status = 0;
    throw offline;
  }
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    if (!res.ok) {
      const e = new Error(text || res.statusText);
      e.status = res.status;
      throw e;
    }
    return text;
  }
  if (!res.ok) {
    const e = new Error(data.error || res.statusText);
    e.status = res.status;
    e.allowed = data.allowed;
    throw e;
  }
  return data;
}

// A failed call must never leave a screen sitting on "Loading...". Every view
// and every action routes its errors through here.
function handleError(err, targetId) {
  const message = err?.message || "Something went wrong.";
  if (err?.status === 401) {
    token = "";
    me = null;
    sessionStorage.removeItem("vr_token");
    renderAuth();
    toast("Your session expired. Please sign in again.");
    return;
  }
  if (err?.status === 409 && Array.isArray(err.allowed) && err.allowed.length) {
    toast(`Not allowed from this stage. Next: ${err.allowed.map(label).join(", ")}`);
  } else {
    toast(message);
  }
  const el = targetId ? document.getElementById(targetId) : null;
  if (el) {
    el.className = "error";
    el.textContent = message;
  }
}

// Disables the button while its action runs, so a double click cannot create
// two pickups or fire two status changes.
async function withBusy(btn, working, fn) {
  if (!btn || btn.disabled) return;
  const original = btn.textContent;
  btn.disabled = true;
  btn.textContent = working;
  try {
    await fn();
  } catch (err) {
    handleError(err);
  } finally {
    if (btn.isConnected) {
      btn.disabled = false;
      btn.textContent = original;
    }
  }
}

function progressHtml(status, timeline) {
  const failed = FAILURE_STATES.includes(status);
  let reached = FLOW.indexOf(status);
  // A failure code is not on the success track, so work out how far the job
  // actually got from its history when we have it.
  if (failed && Array.isArray(timeline)) {
    reached = timeline.reduce((max, h) => Math.max(max, FLOW.indexOf(h.new_status)), -1);
  }
  const segments = FLOW.map(
    (s, n) => `<span class="${n <= reached ? "on" : ""}" title="${esc(label(s))}"></span>`
  ).join("");
  return `<div class="progress${failed ? " failed" : ""}" role="img" aria-label="Progress: ${esc(label(status))}">${segments}</div>
    ${failed ? `<p class="stopped">Stopped — ${esc(label(status))}</p>` : ""}`;
}

function layout(body) {
  const role = me?.role || "";
  app.innerHTML = `
    <header class="topbar">
      <div class="brand">
        <div class="mark" aria-hidden="true"></div>
        <div>
          <h1>VoltRescue</h1>
          <p>Dar es Salaam battery pickup POC</p>
        </div>
      </div>
      <nav class="nav">
        ${role === "citizen" || role === "admin" ? `<button data-go="request" class="${view === "request" ? "active" : ""}">Request pickup</button>` : ""}
        ${role === "citizen" ? `<button data-go="track" class="${view === "track" ? "active" : ""}">Track status</button>` : ""}
        ${role === "collector" || role === "admin" ? `<button data-go="collector" class="${view === "collector" ? "active" : ""}">Collector</button>` : ""}
        ${role === "recycler" || role === "admin" ? `<button data-go="recycler" class="${view === "recycler" ? "active" : ""}">Recycler</button>` : ""}
        ${role === "admin" ? `<button data-go="admin" class="${view === "admin" ? "active" : ""}">Admin</button>` : ""}
        <button data-go="inbox" class="${view === "inbox" ? "active" : ""}">Alerts</button>
        <button data-go="profile" class="${view === "profile" ? "active" : ""}">${me?.name || "Account"}</button>
        <button id="logout" class="btn ghost">Log out</button>
      </nav>
    </header>
    <main>${body}</main>`;
  app.querySelectorAll("[data-go]").forEach((b) =>
    b.addEventListener("click", () => {
      view = b.dataset.go;
      route();
    })
  );
  document.getElementById("logout").onclick = () => {
    token = "";
    me = null;
    sessionStorage.removeItem("vr_token");
    renderAuth();
  };
}

function renderAuth(mode = "login") {
  app.innerHTML = `
    <section class="auth card">
      <div class="brand" style="margin-bottom:12px">
        <div class="mark"></div>
        <div><h1>VoltRescue</h1><p>Sign in to the Dar es Salaam pilot</p></div>
      </div>
      <div class="nav" style="margin-bottom:16px">
        <button class="${mode === "login" ? "active" : ""}" id="tabLogin">Login</button>
        <button class="${mode === "register" ? "active" : ""}" id="tabReg">Register</button>
        <button class="${mode === "reset" ? "active" : ""}" id="tabReset">Reset password</button>
      </div>
      <form id="authForm" class="stack">
        ${
          mode === "register"
            ? `<label>Name <input name="name" required></label>
               <label>Email <input name="email" type="email" required></label>
               <label>Phone <input name="phone" required placeholder="2557XXXXXXXX"></label>
               <label>Password <input name="password" type="password" required minlength="8"></label>
               <label>Role
                 <select name="role">
                   <option value="citizen">Citizen</option>
                   <option value="collector">Collector</option>
                   <option value="recycler">Recycler</option>
                 </select>
               </label>`
            : mode === "reset"
              ? `<label>Phone <input name="phone" required></label>
                 <button class="btn primary" type="submit">Send reset code</button>
                 <label>Code <input name="token"></label>
                 <label>New password <input name="password" type="password" minlength="8"></label>`
              : `<label>Email or phone <input name="identifier" required autocomplete="username" placeholder="you@example.com or 2557XXXXXXXX"></label>
                 <label>Password <input name="password" type="password" required autocomplete="current-password"></label>`
        }
        ${mode !== "reset" ? `<button class="btn primary" type="submit">${mode === "register" ? "Create account" : "Log in"}</button>` : `<button class="btn" type="button" id="confirmReset">Confirm new password</button>`}
        <p class="muted" id="authMsg"></p>
      </form>
      ${mode === "login" ? `<div class="demo-accounts">
        <p class="muted">Pilot demonstration accounts — one click to switch role</p>
        <div class="chips">
          ${DEMO_ACCOUNTS.map((a) => `<button type="button" class="chip" data-demo="${esc(a.email)}">${esc(a.role)}</button>`).join("")}
        </div>
      </div>` : ""}
    </section>`;
  document.getElementById("tabLogin").onclick = () => renderAuth("login");
  document.getElementById("tabReg").onclick = () => renderAuth("register");
  document.getElementById("tabReset").onclick = () => renderAuth("reset");
  app.querySelectorAll("[data-demo]").forEach((b) => {
    b.onclick = () => {
      const form = document.getElementById("authForm");
      form.identifier.value = b.dataset.demo;
      form.password.value = "VoltRescue!23";
      form.requestSubmit();
    };
  });
  document.getElementById("authForm").onsubmit = async (e) => {
    e.preventDefault();
    const fd = Object.fromEntries(new FormData(e.target).entries());
    const msg = document.getElementById("authMsg");
    const submitBtn = e.target.querySelector('button[type="submit"]');
    if (submitBtn?.disabled) return;
    if (submitBtn) submitBtn.disabled = true;
    msg.className = "muted";
    msg.textContent = "";
    try {
      if (mode === "login") {
        const data = await api("/auth/login", { method: "POST", body: JSON.stringify(fd) });
        token = data.token;
        me = data.user;
        sessionStorage.setItem("vr_token", token);
        view = me.role === "admin" ? "admin" : me.role === "collector" ? "collector" : me.role === "recycler" ? "recycler" : "request";
        route();
      } else if (mode === "register") {
        const data = await api("/auth/register", { method: "POST", body: JSON.stringify(fd) });
        token = data.token;
        me = data.user;
        sessionStorage.setItem("vr_token", token);
        view = "request";
        route();
      } else {
        await api("/auth/password-reset", { method: "POST", body: JSON.stringify({ phone: fd.phone }) });
        msg.textContent = "If that phone exists, a code was sent (SMS/WhatsApp sandbox).";
      }
    } catch (err) {
      msg.textContent = err.message;
      msg.className = "error";
    } finally {
      if (submitBtn?.isConnected) submitBtn.disabled = false;
    }
  };
  const cr = document.getElementById("confirmReset");
  if (cr) {
    cr.onclick = async () => {
      const fd = Object.fromEntries(new FormData(document.getElementById("authForm")).entries());
      try {
        await api("/auth/password-reset/confirm", { method: "POST", body: JSON.stringify(fd) });
        toast("Password updated");
        renderAuth("login");
      } catch (err) {
        document.getElementById("authMsg").textContent = err.message;
      }
    };
  }
}

function bindMap(latEl, lngEl) {
  const start = [-6.7924, 39.2083]; // Dar es Salaam city centre
  // The coordinates must always be populated, even if the map never renders.
  latEl.value = start[0].toFixed(6);
  lngEl.value = start[1].toFixed(6);

  let set = (lat, lng) => {
    latEl.value = Number(lat).toFixed(6);
    lngEl.value = Number(lng).toFixed(6);
    const readout = document.getElementById("coords");
    if (readout) readout.textContent = `Pin at ${latEl.value}, ${lngEl.value}`;
  };

  // Leaflet and its tiles come from the public internet. On a venue network
  // that blocks them the form must still work, so fall back to manual entry
  // rather than letting a ReferenceError take out the whole screen.
  const mapEl = document.getElementById("map");
  if (typeof L === "undefined") {
    mapEl.className = "map-fallback";
    mapEl.innerHTML = `<p>Map unavailable — no internet connection.</p>
      <p class="muted">The pickup point defaults to Dar es Salaam city centre. Use <strong>Use my location</strong>, or type the coordinates.</p>
      <label>Latitude <input id="mLat" type="number" step="0.000001" value="${start[0]}"></label>
      <label>Longitude <input id="mLng" type="number" step="0.000001" value="${start[1]}"></label>
      <p class="muted" id="coords">Pin at ${latEl.value}, ${lngEl.value}</p>`;
    document.getElementById("mLat").oninput = (e) => set(e.target.value || start[0], lngEl.value);
    document.getElementById("mLng").oninput = (e) => set(latEl.value, e.target.value || start[1]);
  } else {
    try {
      map = L.map("map").setView(start, 12);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "&copy; OSM", maxZoom: 19 }).addTo(map);
      marker = L.marker(start, { draggable: true }).addTo(map);
      const plot = set;
      set = (lat, lng) => {
        plot(lat, lng);
        marker.setLatLng([Number(lat), Number(lng)]);
      };
      map.on("click", (e) => set(e.latlng.lat, e.latlng.lng));
      marker.on("dragend", () => {
        const p = marker.getLatLng();
        set(p.lat, p.lng);
      });
      set(start[0], start[1]);
    } catch {
      mapEl.className = "map-fallback";
      mapEl.innerHTML = `<p>Map could not be drawn.</p><p class="muted">The pickup point defaults to Dar es Salaam city centre; the request will still submit.</p>`;
    }
  }

  // Bound outside the map branches so GPS capture survives a missing map.
  document.getElementById("geoBtn").onclick = (e) => {
    if (!navigator.geolocation) return toast("This browser cannot provide GPS.");
    const btn = e.currentTarget;
    const original = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Locating…";
    const done = () => {
      btn.disabled = false;
      btn.textContent = original;
    };
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords;
        if (map) map.setView([latitude, longitude], 15);
        set(latitude, longitude);
        toast("Location captured");
        done();
      },
      (err) => {
        toast(err.code === 1 ? "Location permission denied — pin the map instead." : "Could not read GPS. Pin the map instead.");
        done();
      },
      { timeout: 10000 }
    );
  };
}

async function viewRequest() {
  layout(`
    <section class="card">
      <h2>Submit pickup request</h2>
      <p class="muted">Location is stored as GPS. Pin the map or use auto-detect.</p>
      <form id="pickupForm" class="stack">
        <label>Area
          <select name="area">
            <option>Kariakoo</option><option>Kinondoni</option><option>Temeke</option><option>Ilala</option><option>Ubungo</option>
          </select>
        </label>
        <label>Address / landmark <input name="location" required placeholder="Street, building"></label>
        <label>Battery type
          <select name="battery_type">
            ${BATTERY_TYPES.map((t) => `<option>${esc(t)}</option>`).join("")}
          </select>
        </label>
        <label>Quantity <input name="quantity" type="number" min="1" value="4" required></label>
        <label>Remarks <textarea name="remarks"></textarea></label>
        <input type="hidden" name="latitude" id="lat">
        <input type="hidden" name="longitude" id="lng">
        <button type="button" class="btn ghost" id="geoBtn">Use my location</button>
        <div id="map"></div>
        <button class="btn primary" type="submit">Request pickup</button>
        <p id="pickupMsg" class="muted"></p>
      </form>
    </section>`);
  bindMap(document.getElementById("lat"), document.getElementById("lng"));
  document.getElementById("pickupForm").onsubmit = async (e) => {
    e.preventDefault();
    const fd = Object.fromEntries(new FormData(e.target).entries());
    const msg = document.getElementById("pickupMsg");
    const btn = e.target.querySelector('button[type="submit"]');
    msg.className = "muted";
    msg.textContent = "";
    await withBusy(btn, "Saving…", async () => {
      const data = await api("/pickup/create", { method: "POST", body: JSON.stringify(fd) });
      msg.className = "oktext";
      msg.textContent = `Saved as #${data.request.request_id} — ${label(data.request.status)}`;
      toast("Pickup stored in database");
      view = "track";
      route();
    });
  };
}

function card(p, extra = "") {
  const failed = FAILURE_STATES.includes(p.status);
  return `<article class="card${failed ? " is-failed" : ""}" data-id="${esc(p.request_id)}">
    <header style="display:flex;justify-content:space-between;gap:8px;align-items:flex-start">
      <strong>#${esc(p.request_id)} · ${esc(p.location)}</strong>
      <span class="status${failed ? " bad" : ""}" title="${esc(p.status)}">${esc(label(p.status))}</span>
    </header>
    ${progressHtml(p.status)}
    <p>${esc(p.quantity)} × ${esc(p.battery_type)}${p.citizen_name ? " · " + esc(p.citizen_name) : ""}</p>
    ${p.latitude ? `<p class="muted">GPS ${esc(p.latitude)}, ${esc(p.longitude)}
      ${p.nav_link ? ` · <a href="${esc(p.google_nav || p.nav_link)}" target="_blank" rel="noopener">Navigate</a>` : ""}</p>` : ""}
    ${extra}
  </article>`;
}

async function viewTrack() {
  layout(`<section class="grid"><h2>Your requests</h2><div id="list" class="loading">Loading…</div></section>`);
  const list = document.getElementById("list");
  try {
    const data = await api("/pickup");
    list.className = "";
    if (!data.items.length) {
      list.innerHTML = `<div class="empty">You have not requested a pickup yet.
        <p class="muted">Choose <strong>Request pickup</strong> above to book your first collection.</p></div>`;
      return;
    }
    list.className = "grid";
    list.innerHTML = data.items.map((p) => card(p, `<button class="btn" data-open="${esc(p.request_id)}">Open timeline</button>`)).join("");
    list.querySelectorAll("[data-open]").forEach((b) =>
      b.addEventListener("click", () => openDetail(Number(b.dataset.open)))
    );
  } catch (err) {
    list.className = "";
    list.innerHTML = `<p class="error">${esc(err.message)}</p>`;
    handleError(err);
  }
}

async function openDetail(id) {
  let data;
  try {
    data = await api("/pickup/" + id);
  } catch (err) {
    return handleError(err);
  }
  const p = data.request;
  const tl = (p.timeline || [])
    .map((h) => {
      const bad = FAILURE_STATES.includes(h.new_status);
      return `<li><span class="dot ${bad ? "bad" : "done"}"></span><div>
        <strong>${esc(label(h.new_status))}</strong>
        <div class="muted">${esc(h.updated_time)} · ${esc(h.actor_name || "system")}${h.note ? " · " + esc(h.note) : ""}</div>
      </div></li>`;
    })
    .join("");
  const ups = (p.uploads || [])
    .map((u) => `<div><img class="preview" alt="${esc(u.kind)} evidence" src="/${esc(u.file_path)}"><div class="muted">${esc(u.kind)} · ${esc(u.created_at)}</div></div>`)
    .join("");
  const failed = FAILURE_STATES.includes(p.status);
  layout(`<section class="card">
    <button class="btn ghost" id="back">← Back</button>
    <h2>Request #${esc(p.request_id)}</h2>
    ${progressHtml(p.status, p.timeline)}
    <p class="status${failed ? " bad" : ""}" title="${esc(p.status)}">${esc(label(p.status))}</p>
    <p>${esc(p.quantity)} × ${esc(p.battery_type)} at ${esc(p.location)}</p>
    <h3>Timeline</h3>
    <ol class="timeline">${tl || "<li class='muted'>No history yet.</li>"}</ol>
    <h3>Evidence</h3>
    ${ups || "<p class='muted'>No photos yet.</p>"}
    ${me.role !== "citizen" ? `<form id="up" class="stack"><input type="hidden" name="request_id" value="${esc(p.request_id)}">
      <label>Photo kind
        <select name="kind"><option>pickup</option><option>handover</option><option>receipt</option></select>
      </label>
      <input type="file" name="file" accept="image/*" required>
      <button class="btn" type="submit">Upload evidence</button>
      <p class="muted" id="upMsg">JPG, PNG or WebP. Maximum 5 MB.</p></form>` : ""}
  </section>`);
  document.getElementById("back").onclick = route;
  const up = document.getElementById("up");
  if (up) {
    up.onsubmit = async (e) => {
      e.preventDefault();
      const fd = new FormData(up);
      const file = up.querySelector("input[type=file]").files[0];
      const msg = document.getElementById("upMsg");
      if (!file) return;
      // The server caps uploads at 5 MB; say so before spending time encoding.
      if (file.size > 5 * 1024 * 1024) {
        msg.className = "error";
        msg.textContent = `That photo is ${(file.size / 1048576).toFixed(1)} MB. The limit is 5 MB.`;
        return;
      }
      msg.className = "muted";
      msg.textContent = "";
      await withBusy(e.submitter || up.querySelector('button[type="submit"]'), "Uploading…", async () => {
        const bytes = new Uint8Array(await file.arrayBuffer());
        let bin = "";
        bytes.forEach((b) => (bin += String.fromCharCode(b)));
        await api("/uploads", {
          method: "POST",
          body: JSON.stringify({
            request_id: Number(fd.get("request_id")),
            kind: fd.get("kind"),
            mime: file.type,
            data: btoa(bin),
          }),
        });
        toast("Photo stored");
        openDetail(id);
      });
    };
  }
}

async function viewCollector() {
  layout(`<section class="grid"><h2>Collector assignments</h2><div id="list" class="loading">Loading…</div></section>`);
  const list = document.getElementById("list");
  let data, rec;
  try {
    data = await api("/collector/tasks");
    rec = await api("/recyclers").catch(() => ({ items: [] }));
  } catch (err) {
    list.className = "";
    list.innerHTML = `<p class="error">${esc(err.message)}</p>`;
    return handleError(err);
  }
  const recOpts = rec.items.map((r) => `<option value="${esc(r.recycler_id)}">${esc(r.company_name)}</option>`).join("");
  if (!data.items.length) {
    list.className = "";
    list.innerHTML = `<div class="empty">No assignments yet. Jobs appear here as soon as the control room assigns them to you.</div>`;
    return;
  }
  list.className = "grid";
  list.innerHTML = data.items
    .map((p) => {
      const next = COLLECTOR_NEXT[p.status];
      let actions = `<button class="btn" data-open="${p.request_id}">Timeline</button>`;
      if (p.status === "COLLECTOR_ASSIGNED") actions += `<button class="btn primary" data-accept="${p.request_id}">Accept assignment</button>`;
      if (next) actions += `<button class="btn ok" data-next="${esc(next)}" data-id="${esc(p.request_id)}">Mark ${esc(label(next))}</button>`;
      if (p.status === "IN_COLLECTOR_CUSTODY" || p.status === "TRANSFER_SCHEDULED") {
        actions += `<form data-hand="${p.request_id}" class="stack"><select name="recycler_id">${recOpts}</select><button class="btn">Transfer to recycler</button></form>`;
      }
      if (["COLLECTOR_ASSIGNED", "PICKUP_ACCEPTED", "COLLECTOR_EN_ROUTE"].includes(p.status)) {
        actions += `<button class="btn danger" data-fail="NO_SHOW" data-id="${p.request_id}">No-show</button>`;
      }
      return card(p, actions);
    })
    .join("");
  list.querySelectorAll("[data-open]").forEach((b) => (b.onclick = () => openDetail(Number(b.dataset.open))));
  list.querySelectorAll("[data-accept]").forEach((b) => {
    b.onclick = () =>
      withBusy(b, "Accepting…", async () => {
        await api("/collector/accept", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.accept) }) });
        toast("Assignment accepted");
        viewCollector();
      });
  });
  list.querySelectorAll("[data-next]").forEach((b) => {
    b.onclick = () =>
      withBusy(b, "Saving…", async () => {
        await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.id), status: b.dataset.next }) });
        toast(`Status updated to ${label(b.dataset.next)}`);
        viewCollector();
      });
  });
  list.querySelectorAll("[data-fail]").forEach((b) => {
    b.onclick = () => {
      if (!confirm("Report this pickup as a no-show?\n\nThe resident and the control room are notified, and the job leaves your list.")) return;
      withBusy(b, "Reporting…", async () => {
        await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.id), status: b.dataset.fail, note: "Nobody present at the address" }) });
        toast("No-show reported");
        viewCollector();
      });
    };
  });
  list.querySelectorAll("[data-hand]").forEach((f) => {
    f.onsubmit = (e) => {
      e.preventDefault();
      const recycler_id = Number(new FormData(f).get("recycler_id"));
      withBusy(f.querySelector("button"), "Transferring…", async () => {
        await api("/collector/handover", { method: "POST", body: JSON.stringify({ request_id: Number(f.dataset.hand), recycler_id }) });
        toast("Custody transferred to the recycler");
        viewCollector();
      });
    };
  });
}

async function viewRecycler() {
  layout(`<section class="grid"><h2>Incoming batteries</h2><div id="list" class="loading">Loading…</div></section>`);
  const list = document.getElementById("list");
  let data;
  try {
    data = await api("/pickup");
  } catch (err) {
    list.className = "";
    list.innerHTML = `<p class="error">${esc(err.message)}</p>`;
    return handleError(err);
  }
  const items = data.items.filter((p) =>
    ["IN_TRANSIT_TO_RECYCLER", "RECEIVED_BY_RECYCLER", "RECYCLER_VALIDATED", "RECYCLER_REJECTED", "PROCESS_COMPLETED"].includes(p.status)
  );
  if (!items.length) {
    list.className = "";
    list.innerHTML = `<div class="empty">No incoming transfers. Loads appear here once a collector dispatches them to you.</div>`;
    return;
  }
  list.className = "grid";
  list.innerHTML = items
    .map((p) => {
      let a = `<button class="btn" data-open="${p.request_id}">Timeline</button>`;
      if (p.status === "IN_TRANSIT_TO_RECYCLER") a += `<button class="btn primary" data-act="receive" data-id="${p.request_id}">Confirm receipt</button><button class="btn danger" data-act="reject" data-id="${p.request_id}">Reject</button>`;
      if (p.status === "RECEIVED_BY_RECYCLER") a += `<button class="btn ok" data-act="validate" data-id="${p.request_id}">Validate materials</button>`;
      if (p.status === "RECYCLER_VALIDATED") a += `<button class="btn primary" data-act="complete" data-id="${p.request_id}">Complete processing</button>`;
      return card(p, a);
    })
    .join("");
  list.querySelectorAll("[data-open]").forEach((b) => (b.onclick = () => openDetail(Number(b.dataset.open))));
  const ACT_LABEL = { receive: "Receipt confirmed", reject: "Load rejected", validate: "Materials validated", complete: "Processing completed" };
  list.querySelectorAll("[data-act]").forEach((b) => {
    b.onclick = () => {
      if (b.dataset.act === "reject" && !confirm("Reject this load?\n\nCustody returns to the collector and everyone is notified. This is recorded permanently in the audit trail.")) return;
      withBusy(b, "Saving…", async () => {
        await api("/recycler/confirm", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.id), action: b.dataset.act }) });
        toast(ACT_LABEL[b.dataset.act] || "Update saved");
        viewRecycler();
      });
    };
  });
}

async function viewAdmin() {
  layout(`<section class="grid">
    <h2>Operations dashboard</h2>
    <div class="toolbar">
      <input id="q" placeholder="Search location, name, type">
      <select id="st"><option value="">All statuses</option>${FLOW.concat(FAILURE_STATES).map((s)=>`<option value="${esc(s)}">${esc(label(s))}</option>`).join("")}</select>
      <button class="btn" id="apply">Filter</button>
      <a class="btn" href="/api/admin/export" id="export">Export CSV</a>
    </div>
    <div id="kpis" class="kpis"></div>
    <div class="card table-wrap" id="table"><span class="loading">Loading…</span></div>
    <div class="card" id="people"></div>
  </section>`);
  document.getElementById("export").onclick = (e) => {
    e.preventDefault();
    withBusy(e.currentTarget, "Exporting…", async () => {
      const res = await fetch("/api/admin/export", { headers: { Authorization: "Bearer " + token } });
      if (!res.ok) throw Object.assign(new Error("Export failed"), { status: res.status });
      const blob = await res.blob();
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "voltrescue-requests.csv";
      a.click();
      URL.revokeObjectURL(a.href);
      toast("CSV downloaded");
    });
  };
  const KPI_LABEL = {
    today: "Submitted today",
    pending_assignment: "Awaiting assignment",
    assigned: "Assigned / active",
    recycler_pending: "With recycler",
    completed: "Completed",
    failed: "Exceptions",
  };
  const KPI_ORDER = ["today", "pending_assignment", "assigned", "recycler_pending", "completed", "failed"];
  const load = async (page = 1) => {
    const q = document.getElementById("q").value;
    const status = document.getElementById("st").value;
    let dash, users;
    try {
      dash = await api(`/admin/dashboard?q=${encodeURIComponent(q)}&status=${encodeURIComponent(status)}&page=${page}&sort=request_id&dir=desc`);
      users = await api("/admin/users");
    } catch (err) {
      document.getElementById("table").innerHTML = `<p class="error">${esc(err.message)}</p>`;
      return handleError(err);
    }
    document.getElementById("kpis").innerHTML = KPI_ORDER.filter((k) => k in dash.kpis)
      .map((k) => `<div class="kpi${k === "failed" && dash.kpis[k] > 0 ? " warn" : ""}"><strong>${esc(dash.kpis[k])}</strong><span>${esc(KPI_LABEL[k])}</span></div>`)
      .join("");
    const colOpts = users.collectors.map((c) => `<option value="${esc(c.collector_id)}">${esc(c.name)}</option>`).join("");
    document.getElementById("table").innerHTML = dash.items.length
      ? `<table>
        <thead><tr><th>ID</th><th>Citizen</th><th>Where</th><th>Qty</th><th>Status</th><th>Assign / override</th></tr></thead>
        <tbody>
          ${dash.items
            .map(
              (p) => `<tr>
                <td>#${esc(p.request_id)}</td><td>${esc(p.citizen_name)}</td><td>${esc(p.location)}</td><td>${esc(p.quantity)}</td>
                <td class="status${FAILURE_STATES.includes(p.status) ? " bad" : ""}" title="${esc(p.status)}">${esc(label(p.status))}</td>
                <td>
                  <select data-col="${esc(p.request_id)}" aria-label="Collector for request ${esc(p.request_id)}">${colOpts}</select>
                  <button class="btn" data-assign="${esc(p.request_id)}">Assign</button>
                  <select data-ov="${esc(p.request_id)}" aria-label="Override status for request ${esc(p.request_id)}">${FLOW.concat(FAILURE_STATES).map((s)=>`<option value="${esc(s)}" ${s===p.status?"selected":""}>${esc(label(s))}</option>`).join("")}</select>
                  <button class="btn danger" data-over="${esc(p.request_id)}">Override</button>
                </td>
              </tr>`
            )
            .join("")}
        </tbody>
      </table>
      <p class="muted">Page ${esc(dash.page)} · ${esc(dash.total)} rows
        <button class="btn ghost" ${dash.page <= 1 ? "disabled" : ""} id="prev">Prev</button>
        <button class="btn ghost" ${dash.page * dash.size >= dash.total ? "disabled" : ""} id="next">Next</button></p>
      <p class="muted">Collector workload: ${esc(dash.workload.map((w) => w.name + " (" + w.jobs + ")").join(", ")) || "none"}</p>`
      : `<div class="empty">No requests match that filter.</div>
         <p class="muted"><button class="btn ghost" id="prev" disabled>Prev</button>
         <button class="btn ghost" id="next" disabled>Next</button></p>`;
    document.getElementById("people").innerHTML = `
      <h3>User management</h3>
      <form id="newUser" class="stack">
        <input name="name" placeholder="Name" required>
        <input name="phone" placeholder="2557..." required>
        <input name="email" placeholder="email" required>
        <select name="role"><option>citizen</option><option>collector</option><option>recycler</option><option>admin</option></select>
        <input name="password" placeholder="Password (min 8)" value="VoltRescue!23">
        <button class="btn primary">Create user</button>
      </form>
      <div class="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Phone</th></tr></thead>
      <tbody>${users.users.map((u) => `<tr><td>${esc(u.name)}</td><td>${esc(u.role)}</td><td>${esc(u.phone)}</td></tr>`).join("")}</tbody></table></div>
      <p><a class="btn" id="auditBtn">Audit logs</a>
         · <button class="btn ghost" id="mpesa">M-Pesa sandbox auth</button>
         · <button class="btn ghost" id="notifQ">Process notification queue</button></p>
      <p class="muted" id="notifStats"></p>`;
    document.getElementById("prev").onclick = () => load(page - 1);
    document.getElementById("next").onclick = () => load(page + 1);
    document.querySelectorAll("[data-assign]").forEach((b) => {
      b.onclick = () =>
        withBusy(b, "Assigning…", async () => {
          const collector_id = Number(document.querySelector(`[data-col="${b.dataset.assign}"]`).value);
          await api("/admin/assign", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.assign), collector_id }) });
          toast("Collector assigned");
          load(page);
        });
    });
    document.querySelectorAll("[data-over]").forEach((b) => {
      b.onclick = () => {
        const status = document.querySelector(`[data-ov="${b.dataset.over}"]`).value;
        // An override bypasses the lifecycle rules, so make it a deliberate act.
        if (!confirm(`Force request #${b.dataset.over} to "${label(status)}"?\n\nThis bypasses the normal workflow rules and is recorded in the audit trail as an override, under your name.`)) return;
        withBusy(b, "Overriding…", async () => {
          await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.over), status, override: true, note: "Admin override" }) });
          toast(`Request #${b.dataset.over} forced to ${label(status)}`);
          load(page);
        });
      };
    });
    document.getElementById("newUser").onsubmit = (e) => {
      e.preventDefault();
      const form = e.target;
      withBusy(form.querySelector("button"), "Creating…", async () => {
        await api("/admin/users", { method: "POST", body: JSON.stringify(Object.fromEntries(new FormData(form).entries())) });
        toast("User created");
        load(page);
      });
    };
    document.getElementById("auditBtn").onclick = (e) =>
      withBusy(e.currentTarget, "Loading…", async () => {
        const logs = await api("/audit/logs");
        view = "audit";
        layout(`<section class="card"><h2>Audit log</h2><button class="btn ghost" id="back">← Back to dashboard</button>
          <p class="muted">Newest first. Every entry is written by the server, not the interface.</p>
          <div class="table-wrap"><table><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>Record</th></tr></thead>
          <tbody>${logs.items.map((l) => `<tr><td>${esc(l.timestamp)}</td><td>${esc(l.action)}</td><td>${esc(l.actor_name || l.actor || "system")}</td><td>${esc(l.entity)} ${esc(l.entity_id)}</td></tr>`).join("")}</tbody></table></div></section>`);
        document.getElementById("back").onclick = () => {
          view = "admin";
          viewAdmin();
        };
      });
    document.getElementById("mpesa").onclick = (e) =>
      withBusy(e.currentTarget, "Checking…", async () => {
        const r = await api("/mpesa/sandbox/auth");
        toast(r.sandbox ? "M-Pesa sandbox connector ready — no live transactions" : "M-Pesa auth returned");
      });
    const showNotifStats = async () => {
      try {
        const s = await api("/notifications/stats");
        const counts = s.by_channel.map((c) => `${c.channel}/${c.status}: ${c.total}`).join(" · ");
        document.getElementById("notifStats").textContent =
          `Notifications — ${counts || "none yet"} · queue pending: ${s.queue_pending} · provider: ${s.live_provider ? "live" : "sandbox (no API key)"}`;
      } catch {
        document.getElementById("notifStats").textContent = "Notification statistics unavailable.";
      }
    };
    document.getElementById("notifQ").onclick = (e) =>
      withBusy(e.currentTarget, "Processing…", async () => {
        const r = await api("/notifications/process", { method: "POST" });
        toast(`Queue processed: ${r.processed} sent, ${r.pending} still pending`);
        showNotifStats();
      });
    showNotifStats();
  };
  document.getElementById("apply").onclick = () => load(1);
  document.getElementById("q").addEventListener("keydown", (e) => {
    if (e.key === "Enter") load(1);
  });
  document.getElementById("st").onchange = () => load(1);
  load(1);
}

async function viewInbox() {
  layout(`<section class="card"><h2>Notifications</h2>
    <p class="muted">Every message the platform has sent to you. In the pilot these are written to the database rather than billed to a live gateway.</p>
    <div id="n" class="loading">Loading…</div></section>`);
  const box = document.getElementById("n");
  let data;
  try {
    data = await api("/notifications");
  } catch (err) {
    box.className = "";
    box.innerHTML = `<p class="error">${esc(err.message)}</p>`;
    return handleError(err);
  }
  box.className = "";
  box.innerHTML = data.items.length
    ? `<ul class="alerts">${data.items
        .map(
          (n) => `<li><div><strong>${esc(n.channel)}</strong> <span class="pill">${esc(n.status)}</span></div>
            <div>${esc(n.message)}</div><div class="muted">${esc(n.created_at)}</div></li>`
        )
        .join("")}</ul>`
    : `<div class="empty">No alerts yet. Messages arrive here as your pickups move through the process.</div>`;
}

async function viewProfile() {
  layout(`<section class="card"><h2>Profile</h2>
    <form id="pf" class="stack">
      <label>Name <input name="name" value="${esc(me.name)}" required></label>
      <label>Email <input name="email" type="email" value="${esc(me.email)}" required></label>
      <button class="btn primary" type="submit">Save</button>
    </form>
    <p class="muted">Role: ${esc(me.role)} · Phone ${esc(me.phone)}</p>
    <p class="muted">Battery recognition from photos, reward points, recycling certificates and commercial analytics are Phase 2 — the data model reserves space for them but nothing is wired up.</p>
  </section>`);
  document.getElementById("pf").onsubmit = (e) => {
    e.preventDefault();
    const form = e.target;
    withBusy(form.querySelector("button"), "Saving…", async () => {
      await api("/auth/me", { method: "PUT", body: JSON.stringify(Object.fromEntries(new FormData(form).entries())) });
      me = (await api("/auth/me")).user;
      toast("Profile saved");
      route();
    });
  };
}

async function route() {
  if (!token || !me) return renderAuth();
  const pages = { request: viewRequest, track: viewTrack, collector: viewCollector, recycler: viewRecycler, admin: viewAdmin, inbox: viewInbox, profile: viewProfile };
  try {
    await (pages[view] || viewRequest)();
  } catch (err) {
    handleError(err);
  }
}

async function boot() {
  if (token) {
    try {
      me = (await api("/auth/me")).user;
      view = me.role === "admin" ? "admin" : me.role === "collector" ? "collector" : me.role === "recycler" ? "recycler" : "request";
      return route();
    } catch {
      token = "";
      sessionStorage.removeItem("vr_token");
    }
  }
  renderAuth();
}

boot();

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
  const res = await fetch("/api" + path, { ...opts, headers });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    if (!res.ok) throw new Error(text || res.statusText);
    return text;
  }
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}

function progressHtml(status) {
  const i = FLOW.indexOf(status);
  return `<div class="progress" aria-label="lifecycle">${FLOW.map((s, n) => `<span class="${n <= i ? "on" : ""}" title="${s}"></span>`).join("")}</div>`;
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
              : `<label>Email or phone <input name="identifier" required value="admin@voltrescue.local"></label>
                 <label>Password <input name="password" type="password" required value="VoltRescue!23"></label>`
        }
        ${mode !== "reset" ? `<button class="btn primary" type="submit">${mode === "register" ? "Create account" : "Log in"}</button>` : `<button class="btn" type="button" id="confirmReset">Confirm new password</button>`}
        <p class="muted" id="authMsg">Demo: citizen@ / collector@ / recycler@ / admin@voltrescue.local · VoltRescue!23</p>
      </form>
    </section>`;
  document.getElementById("tabLogin").onclick = () => renderAuth("login");
  document.getElementById("tabReg").onclick = () => renderAuth("register");
  document.getElementById("tabReset").onclick = () => renderAuth("reset");
  document.getElementById("authForm").onsubmit = async (e) => {
    e.preventDefault();
    const fd = Object.fromEntries(new FormData(e.target).entries());
    const msg = document.getElementById("authMsg");
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
  const start = [-6.7924, 39.2083];
  map = L.map("map").setView(start, 12);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: "&copy; OSM" }).addTo(map);
  marker = L.marker(start, { draggable: true }).addTo(map);
  const set = (lat, lng) => {
    latEl.value = lat.toFixed(6);
    lngEl.value = lng.toFixed(6);
    marker.setLatLng([lat, lng]);
  };
  set(start[0], start[1]);
  map.on("click", (e) => set(e.latlng.lat, e.latlng.lng));
  marker.on("dragend", () => {
    const p = marker.getLatLng();
    set(p.lat, p.lng);
  });
  document.getElementById("geoBtn").onclick = () => {
    if (!navigator.geolocation) return toast("Geolocation not available");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords;
        map.setView([latitude, longitude], 15);
        set(latitude, longitude);
      },
      () => toast("Could not read GPS")
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
            <option>Lead-acid</option><option>Li-ion</option><option>Mixed household</option><option>Automotive</option>
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
    try {
      const data = await api("/pickup/create", { method: "POST", body: JSON.stringify(fd) });
      msg.className = "oktext";
      msg.textContent = "Saved as #" + data.request.request_id + " · " + data.request.status;
      toast("Pickup stored in database");
      view = "track";
      route();
    } catch (err) {
      msg.className = "error";
      msg.textContent = err.message;
    }
  };
}

function card(p, extra = "") {
  return `<article class="card" data-id="${p.request_id}">
    <header style="display:flex;justify-content:space-between;gap:8px">
      <strong>#${p.request_id} · ${p.location}</strong>
      <span class="status">${p.status}</span>
    </header>
    ${progressHtml(p.status)}
    <p>${p.quantity} × ${p.battery_type}${p.citizen_name ? " · " + p.citizen_name : ""}</p>
    ${p.latitude ? `<p class="muted">GPS ${p.latitude}, ${p.longitude}
      ${p.nav_link ? ` · <a href="${p.google_nav || p.nav_link}" target="_blank" rel="noopener">Navigate</a>` : ""}</p>` : ""}
    ${extra}
  </article>`;
}

async function viewTrack() {
  layout(`<section class="grid"><h2>Your requests</h2><div id="list" class="loading">Loading…</div></section>`);
  try {
    const data = await api("/pickup");
    const list = document.getElementById("list");
    if (!data.items.length) {
      list.innerHTML = `<div class="empty">No pickup requests yet.</div>`;
      return;
    }
    list.className = "grid";
    list.innerHTML = data.items.map((p) => card(p, `<button class="btn" data-open="${p.request_id}">Open timeline</button>`)).join("");
    list.querySelectorAll("[data-open]").forEach((b) =>
      b.addEventListener("click", () => openDetail(Number(b.dataset.open)))
    );
  } catch (err) {
    document.getElementById("list").innerHTML = `<p class="error">${err.message}</p>`;
  }
}

async function openDetail(id) {
  const data = await api("/pickup/" + id);
  const p = data.request;
  const tl = (p.timeline || [])
    .map(
      (h) => `<li><span class="dot done"></span><div><strong>${h.new_status}</strong><div class="muted">${h.updated_time} · ${h.actor_name || "system"} ${h.note ? " · " + h.note : ""}</div></div></li>`
    )
    .join("");
  const ups = (p.uploads || [])
    .map((u) => `<div><img class="preview" alt="${u.kind}" src="/${u.file_path}"><div class="muted">${u.kind} · ${u.created_at}</div></div>`)
    .join("");
  layout(`<section class="card">
    <button class="btn ghost" id="back">Back</button>
    <h2>Request #${p.request_id}</h2>
    ${progressHtml(p.status)}
    <p class="status">${p.status}</p>
    <p>${p.quantity} × ${p.battery_type} at ${p.location}</p>
    <h3>Timeline</h3>
    <ol class="timeline">${tl || "<li>No history</li>"}</ol>
    <h3>Evidence</h3>
    ${ups || "<p class='muted'>No photos yet.</p>"}
    ${me.role !== "citizen" ? `<form id="up" class="stack"><input type="hidden" name="request_id" value="${p.request_id}">
      <label>Photo kind
        <select name="kind"><option>pickup</option><option>handover</option><option>receipt</option></select>
      </label>
      <input type="file" name="file" accept="image/*" required>
      <button class="btn">Upload evidence</button></form>` : ""}
  </section>`);
  document.getElementById("back").onclick = route;
  const up = document.getElementById("up");
  if (up) {
    up.onsubmit = async (e) => {
      e.preventDefault();
      const fd = new FormData(up);
      const file = up.querySelector('input[type=file]').files[0];
      const buf = await file.arrayBuffer();
      const bytes = new Uint8Array(buf);
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
    };
  }
}

async function viewCollector() {
  layout(`<section class="grid"><h2>Collector assignments</h2><div id="list" class="loading">Loading…</div></section>`);
  const data = await api("/collector/tasks");
  const rec = await api("/recyclers").catch(() => ({ items: [] }));
  const recOpts = rec.items.map((r) => `<option value="${r.recycler_id}">${r.company_name}</option>`).join("");
  const list = document.getElementById("list");
  if (!data.items.length) {
    list.innerHTML = `<div class="empty">No assignments yet.</div>`;
    return;
  }
  list.className = "grid";
  list.innerHTML = data.items
    .map((p) => {
      const next = COLLECTOR_NEXT[p.status];
      let actions = `<button class="btn" data-open="${p.request_id}">Timeline</button>`;
      if (p.status === "COLLECTOR_ASSIGNED") actions += `<button class="btn primary" data-accept="${p.request_id}">Accept assignment</button>`;
      if (next) actions += `<button class="btn ok" data-next="${next}" data-id="${p.request_id}">Mark ${next}</button>`;
      if (p.status === "IN_COLLECTOR_CUSTODY" || p.status === "TRANSFER_SCHEDULED") {
        actions += `<form data-hand="${p.request_id}" class="stack"><select name="recycler_id">${recOpts}</select><button class="btn">Transfer to recycler</button></form>`;
      }
      if (["COLLECTOR_ASSIGNED", "PICKUP_ACCEPTED", "COLLECTOR_EN_ROUTE"].includes(p.status)) {
        actions += `<button class="btn danger" data-fail="NO_SHOW" data-id="${p.request_id}">No-show</button>`;
      }
      return card(p, actions);
    })
    .join("");
  list.querySelectorAll("[data-open]").forEach((b) => b.onclick = () => openDetail(Number(b.dataset.open)));
  list.querySelectorAll("[data-accept]").forEach((b) => {
    b.onclick = async () => {
      await api("/collector/accept", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.accept) }) });
      toast("Accepted");
      viewCollector();
    };
  });
  list.querySelectorAll("[data-next]").forEach((b) => {
    b.onclick = async () => {
      await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.id), status: b.dataset.next }) });
      toast("Status saved");
      viewCollector();
    };
  });
  list.querySelectorAll("[data-fail]").forEach((b) => {
    b.onclick = async () => {
      await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.id), status: b.dataset.fail, note: "No show" }) });
      viewCollector();
    };
  });
  list.querySelectorAll("[data-hand]").forEach((f) => {
    f.onsubmit = async (e) => {
      e.preventDefault();
      const recycler_id = Number(new FormData(f).get("recycler_id"));
      await api("/collector/handover", { method: "POST", body: JSON.stringify({ request_id: Number(f.dataset.hand), recycler_id }) });
      toast("Handover recorded");
      viewCollector();
    };
  });
}

async function viewRecycler() {
  layout(`<section class="grid"><h2>Incoming batteries</h2><div id="list" class="loading">Loading…</div></section>`);
  const data = await api("/pickup");
  const list = document.getElementById("list");
  const items = data.items.filter((p) =>
    ["IN_TRANSIT_TO_RECYCLER", "RECEIVED_BY_RECYCLER", "RECYCLER_VALIDATED", "RECYCLER_REJECTED", "PROCESS_COMPLETED"].includes(p.status)
  );
  if (!items.length) {
    list.innerHTML = `<div class="empty">No incoming transfers.</div>`;
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
  list.querySelectorAll("[data-act]").forEach((b) => {
    b.onclick = async () => {
      await api("/recycler/confirm", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.id), action: b.dataset.act }) });
      toast("Recycler update saved");
      viewRecycler();
    };
  });
}

async function viewAdmin() {
  layout(`<section class="grid">
    <h2>Operations dashboard</h2>
    <div class="toolbar">
      <input id="q" placeholder="Search location, name, type">
      <select id="st"><option value="">All statuses</option>${FLOW.concat(["CANCELLED","REJECTED","NO_SHOW","TRANSFER_FAILED","RECYCLER_REJECTED"]).map((s)=>`<option>${s}</option>`).join("")}</select>
      <button class="btn" id="apply">Filter</button>
      <a class="btn" href="/api/admin/export" id="export">Export CSV</a>
    </div>
    <div id="kpis" class="kpis"></div>
    <div class="card table-wrap" id="table">Loading…</div>
    <div class="card" id="people"></div>
  </section>`);
  document.getElementById("export").onclick = async (e) => {
    e.preventDefault();
    const res = await fetch("/api/admin/export", { headers: { Authorization: "Bearer " + token } });
    const blob = await res.blob();
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "voltrescue-requests.csv";
    a.click();
  };
  const load = async (page = 1) => {
    const q = document.getElementById("q").value;
    const status = document.getElementById("st").value;
    const dash = await api(`/admin/dashboard?q=${encodeURIComponent(q)}&status=${encodeURIComponent(status)}&page=${page}&sort=request_id&dir=desc`);
    const users = await api("/admin/users");
    document.getElementById("kpis").innerHTML = Object.entries(dash.kpis)
      .map(([k, v]) => `<div class="kpi"><strong>${v}</strong><span>${k.replaceAll("_", " ")}</span></div>`)
      .join("");
    const colOpts = users.collectors.map((c) => `<option value="${c.collector_id}">${c.name}</option>`).join("");
    document.getElementById("table").innerHTML = `
      <table>
        <thead><tr><th>ID</th><th>Citizen</th><th>Where</th><th>Qty</th><th>Status</th><th>Assign / override</th></tr></thead>
        <tbody>
          ${dash.items
            .map(
              (p) => `<tr>
                <td>#${p.request_id}</td><td>${p.citizen_name}</td><td>${p.location}</td><td>${p.quantity}</td>
                <td class="status">${p.status}</td>
                <td>
                  <select data-col="${p.request_id}">${colOpts}</select>
                  <button class="btn" data-assign="${p.request_id}">Assign</button>
                  <select data-ov="${p.request_id}">${FLOW.concat(["CANCELLED","REJECTED","NO_SHOW","TRANSFER_FAILED","RECYCLER_REJECTED"]).map((s)=>`<option ${s===p.status?"selected":""}>${s}</option>`).join("")}</select>
                  <button class="btn danger" data-over="${p.request_id}">Override</button>
                </td>
              </tr>`
            )
            .join("")}
        </tbody>
      </table>
      <p class="muted">Page ${dash.page} · ${dash.total} rows
        <button class="btn ghost" ${dash.page <= 1 ? "disabled" : ""} id="prev">Prev</button>
        <button class="btn ghost" id="next">Next</button></p>
      <p class="muted">Collector workload: ${dash.workload.map((w) => w.name + " (" + w.jobs + ")").join(", ") || "none"}</p>`;
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
      <tbody>${users.users.map((u) => `<tr><td>${u.name}</td><td>${u.role}</td><td>${u.phone}</td></tr>`).join("")}</tbody></table></div>
      <p><a class="btn" id="auditBtn">Audit logs</a>
         · <button class="btn ghost" id="mpesa">M-Pesa sandbox auth</button>
         · <button class="btn ghost" id="notifQ">Process notification queue</button></p>
      <p class="muted" id="notifStats"></p>`;
    document.getElementById("prev").onclick = () => load(page - 1);
    document.getElementById("next").onclick = () => load(page + 1);
    document.querySelectorAll("[data-assign]").forEach((b) => {
      b.onclick = async () => {
        const collector_id = Number(document.querySelector(`[data-col="${b.dataset.assign}"]`).value);
        await api("/admin/assign", { method: "POST", body: JSON.stringify({ request_id: Number(b.dataset.assign), collector_id }) });
        toast("Collector assigned");
        load(page);
      };
    });
    document.querySelectorAll("[data-over]").forEach((b) => {
      b.onclick = async () => {
        const status = document.querySelector(`[data-ov="${b.dataset.over}"]`).value;
        await api("/pickup/status", { method: "PUT", body: JSON.stringify({ request_id: Number(b.dataset.over), status, override: true, note: "Admin override" }) });
        load(page);
      };
    });
    document.getElementById("newUser").onsubmit = async (e) => {
      e.preventDefault();
      await api("/admin/users", { method: "POST", body: JSON.stringify(Object.fromEntries(new FormData(e.target).entries())) });
      toast("User created");
      load(page);
    };
    document.getElementById("auditBtn").onclick = async () => {
      view = "audit";
      const logs = await api("/audit/logs");
      layout(`<section class="card"><h2>Audit logs</h2><button class="btn ghost" id="back">Back</button>
        <table><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>Entity</th></tr></thead>
        <tbody>${logs.items.map((l) => `<tr><td>${l.timestamp}</td><td>${l.action}</td><td>${l.actor_name || l.actor}</td><td>${l.entity} ${l.entity_id}</td></tr>`).join("")}</tbody></table></section>`);
      document.getElementById("back").onclick = () => {
        view = "admin";
        viewAdmin();
      };
    };
    document.getElementById("mpesa").onclick = async () => {
      const r = await api("/mpesa/sandbox/auth");
      toast(r.sandbox ? "M-Pesa sandbox connector ready" : "M-Pesa auth returned");
    };
    const showNotifStats = async () => {
      const s = await api("/notifications/stats");
      const counts = s.by_channel.map((c) => `${c.channel}/${c.status}: ${c.total}`).join(" · ");
      document.getElementById("notifStats").textContent =
        `Notifications — ${counts || "none yet"} · queue pending: ${s.queue_pending} · provider: ${s.live_provider ? "live" : "sandbox (no API key)"}`;
    };
    document.getElementById("notifQ").onclick = async () => {
      const r = await api("/notifications/process", { method: "POST" });
      toast(`Queue processed: ${r.processed}, pending: ${r.pending}`);
      showNotifStats();
    };
    showNotifStats();
  };
  document.getElementById("apply").onclick = () => load(1);
  load(1);
}

async function viewInbox() {
  layout(`<section class="card"><h2>Notifications</h2><div id="n" class="loading">Loading…</div></section>`);
  const data = await api("/notifications");
  document.getElementById("n").innerHTML = data.items.length
    ? `<ul>${data.items.map((n) => `<li><strong>${n.channel}</strong> · ${n.status}<div>${n.message}</div><div class="muted">${n.created_at}</div></li>`).join("")}</ul>`
    : `<div class="empty">No alerts yet.</div>`;
}

async function viewProfile() {
  layout(`<section class="card"><h2>Profile</h2>
    <form id="pf" class="stack">
      <label>Name <input name="name" value="${me.name}"></label>
      <label>Email <input name="email" value="${me.email}"></label>
      <button class="btn primary">Save</button>
    </form>
    <p class="muted">Role: ${me.role} · Phone ${me.phone}</p>
    <p class="muted">AI recognition, rewards, certificates and commercial analytics are Phase 2 hooks only.</p>
  </section>`);
  document.getElementById("pf").onsubmit = async (e) => {
    e.preventDefault();
    await api("/auth/me", { method: "PUT", body: JSON.stringify(Object.fromEntries(new FormData(e.target).entries())) });
    me = (await api("/auth/me")).user;
    toast("Profile saved");
    route();
  };
}

async function route() {
  if (!token || !me) return renderAuth();
  const pages = { request: viewRequest, track: viewTrack, collector: viewCollector, recycler: viewRecycler, admin: viewAdmin, inbox: viewInbox, profile: viewProfile };
  await (pages[view] || viewRequest)();
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

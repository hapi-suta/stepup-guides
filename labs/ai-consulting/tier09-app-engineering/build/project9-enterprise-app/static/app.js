// Plain-JavaScript frontend for Project 9. No framework, no build tool.
// It calls the same API you test with curl. The session cookie is sent
// automatically by the browser (credentials: 'same-origin').

const $ = (id) => document.getElementById(id);

async function api(path, method = "GET", body = null) {
  const opts = { method, headers: {}, credentials: "same-origin" };
  if (body) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(path, opts);
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

// --- Login ---------------------------------------------------------------
$("login-btn").onclick = async () => {
  const email = $("email").value.trim();
  const r = await api("/login", "POST", { email });
  if (!r.ok) { $("who").textContent = "Login failed: " + (r.data.detail || r.status); return; }
  $("who").textContent = `Signed in as ${r.data.username} (${r.data.role})`;
  $("ask-box").classList.remove("hidden");
  if (r.data.role === "admin") $("admin-box").classList.remove("hidden");
};

// --- Ask -----------------------------------------------------------------
$("ask-btn").onclick = async () => {
  const query = $("query").value.trim();
  if (!query) return;
  $("answer").textContent = "Thinking...";
  const r = await api("/ask", "POST", { query });
  if (!r.ok) { $("answer").textContent = "Error: " + (r.data.detail || r.status); return; }
  const cites = (r.data.citations || []).map((c) => `[${c.n}] ${c.source}`).join("  ");
  $("answer").textContent = `${r.data.answer}\n\nSources: ${cites || "none"}\n(${r.data.latency_ms} ms, ${r.data.generator})`;
};

// --- Admin: enqueue ingestion + view queue -------------------------------
$("ingest-btn").onclick = async () => {
  const body = {
    title: $("doc-title").value.trim(),
    source: $("doc-source").value.trim(),
    body: $("doc-body").value,
    access_level: 1,
  };
  const r = await api("/admin/ingest", "POST", body);
  $("admin-out").textContent = r.ok
    ? `Enqueued job ${r.data.job_id} (status: ${r.data.status}). The worker will process it.`
    : "Error: " + (r.data.detail || r.status);
};

$("jobs-btn").onclick = async () => {
  const r = await api("/admin/jobs");
  if (!r.ok) { $("admin-out").textContent = "Error: " + (r.data.detail || r.status); return; }
  $("admin-out").textContent = (r.data.jobs || [])
    .map((j) => `#${j.id} ${j.status.padEnd(10)} ${j.source} (attempts ${j.attempts})`)
    .join("\n") || "queue empty";
};

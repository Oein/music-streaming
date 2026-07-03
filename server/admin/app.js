const $ = (id) => document.getElementById(id);
let token = localStorage.getItem("token");
let scanPoll = null;

// Supported audio extensions the server can index.
const EXTENSIONS = ["mp3", "flac", "wav", "ogg", "m4a"];

// Build a labelled checkbox. `onChange` receives the new checked state.
function extCheckbox(ext, checked, onChange) {
  const label = document.createElement("label");
  label.style.cssText = "display:inline-flex;align-items:center;gap:4px;margin-right:10px;";
  const cb = document.createElement("input");
  cb.type = "checkbox";
  cb.checked = checked;
  cb.onchange = () => onChange(cb.checked);
  label.append(cb, document.createTextNode(ext));
  return label;
}

async function api(path, opts = {}) {
  const res = await fetch(path, {
    ...opts,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(opts.headers || {}),
    },
  });
  if (res.status === 401) {
    logout();
    throw new Error("unauthorized");
  }
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || res.statusText);
  const ct = res.headers.get("content-type") || "";
  return ct.includes("application/json") ? res.json() : res.text();
}

function showApp(loggedIn) {
  $("loginCard").classList.toggle("hidden", loggedIn);
  $("app").classList.toggle("hidden", !loggedIn);
  $("logoutBtn").classList.toggle("hidden", !loggedIn);
}

function logout() {
  token = null;
  localStorage.removeItem("token");
  if (scanPoll) clearInterval(scanPoll);
  showApp(false);
}

async function login() {
  $("loginError").textContent = "";
  try {
    const data = await api("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ username: $("username").value, password: $("password").value }),
    });
    token = data.token;
    localStorage.setItem("token", token);
    showApp(true);
    refreshAll();
  } catch (e) {
    $("loginError").textContent = e.message;
  }
}

async function refreshStats() {
  const s = await api("/api/admin/stats");
  $("statAlbums").textContent = s.albums;
  $("statTracks").textContent = s.tracks;
  $("statPlaylists").textContent = s.playlists;
}

// Extensions selected for a new folder (empty = all).
const addExts = new Set();

function renderAddExtensions() {
  const box = $("addExtensions");
  box.querySelectorAll("label").forEach((el) => el.remove());
  for (const ext of EXTENSIONS) {
    box.append(
      extCheckbox(ext, addExts.has(ext), (checked) => {
        checked ? addExts.add(ext) : addExts.delete(ext);
      })
    );
  }
}

async function refreshFolders() {
  const folders = await api("/api/admin/folders");
  const ul = $("folderList");
  ul.innerHTML = "";
  if (folders.length === 0) ul.innerHTML = '<li class="muted">No folders yet.</li>';
  for (const f of folders) {
    const li = document.createElement("li");
    li.style.flexDirection = "column";
    li.style.alignItems = "stretch";

    const topRow = document.createElement("div");
    topRow.className = "row";
    topRow.style.justifyContent = "space-between";
    const left = document.createElement("span");
    left.textContent = f.path;
    const right = document.createElement("div");
    right.className = "row";
    const scanOne = document.createElement("button");
    scanOne.className = "secondary";
    scanOne.textContent = "Scan";
    scanOne.onclick = () => startScan(f.id);
    const del = document.createElement("button");
    del.className = "secondary";
    del.textContent = "✕";
    del.onclick = async () => {
      await api(`/api/admin/folders/${f.id}`, { method: "DELETE" });
      refreshFolders();
    };
    right.append(scanOne, del);
    topRow.append(left, right);

    // Per-folder extension filter, editable inline (saves on change).
    const selected = new Set(
      (f.extensions || "").split(",").map((s) => s.trim()).filter(Boolean)
    );
    const extRow = document.createElement("div");
    extRow.className = "row";
    extRow.style.cssText = "flex-wrap:wrap;margin-top:6px;";
    const lbl = document.createElement("span");
    lbl.className = "muted";
    lbl.textContent = selected.size ? "Only:" : "All types";
    extRow.append(lbl);
    for (const ext of EXTENSIONS) {
      extRow.append(
        extCheckbox(ext, selected.has(ext), async (checked) => {
          checked ? selected.add(ext) : selected.delete(ext);
          lbl.textContent = selected.size ? "Only:" : "All types";
          await api(`/api/admin/folders/${f.id}`, {
            method: "PATCH",
            body: JSON.stringify({ extensions: [...selected] }),
          });
        })
      );
    }

    li.append(topRow, extRow);
    ul.append(li);
  }
}

async function addFolder() {
  const path = $("folderPath").value.trim();
  if (!path) return;
  try {
    await api("/api/admin/folders", {
      method: "POST",
      body: JSON.stringify({ path, extensions: [...addExts] }),
    });
    $("folderPath").value = "";
    addExts.clear();
    renderAddExtensions();
    refreshFolders();
  } catch (e) {
    alert(e.message);
  }
}

async function startScan(folderId) {
  try {
    await api("/api/admin/scan", {
      method: "POST",
      body: JSON.stringify(folderId ? { folderId } : {}),
    });
    pollScan();
  } catch (e) {
    alert(e.message);
  }
}

function pollScan() {
  if (scanPoll) clearInterval(scanPoll);
  scanPoll = setInterval(async () => {
    const s = await api("/api/admin/scan/status");
    const pct = s.filesFound ? Math.round((s.filesProcessed / s.filesFound) * 100) : 0;
    $("scanBar").style.width = pct + "%";
    $("scanState").textContent = s.running ? "Scanning…" : "Idle";
    $("scanDetail").textContent = s.folderPath
      ? `${s.folderPath} — ${s.filesProcessed}/${s.filesFound} · +${s.added} added, ${s.updated} updated, ${s.removed || 0} removed, ${s.errors} errors`
      : "";
    if (!s.running) {
      clearInterval(scanPoll);
      scanPoll = null;
      refreshStats();
    }
  }, 700);
}

function refreshAll() {
  renderAddExtensions();
  refreshStats();
  refreshFolders();
  pollScan();
}

$("loginForm").onsubmit = (e) => {
  e.preventDefault();
  login();
};
$("logoutBtn").onclick = logout;
$("addFolderBtn").onclick = addFolder;
$("scanBtn").onclick = () => startScan(null);

if (token) {
  showApp(true);
  refreshAll();
} else {
  showApp(false);
}

// Seat bot: plays one HUMAN seat against a LIVE Firebase project, so a single
// phone can test online invite play. Anonymous auth, Firebase JS client SDK,
// same env config as live-smoke.mjs (no secrets in this file).
//
//   cd functions/scripts && npm install
//   export GOOGLE_SERVICES_JSON=/home/box/secrets/marge-firebase/google-services.json
//   node seat-bot.mjs --host                 # creates room, prints code, starts when a human joins
//   node seat-bot.mjs --join ABC234          # joins the phone's room, waits for host to start
// Flags: --timeout-min 90  --leave-after-turns N  --name "Box Tester"  --claim 100
//        --ante 10 --seats 2 --bots 0 (host only)  --pace 2000-4000 (ms between actions)
//        --code-file /workspace/online-qa/seatbot-current-code.txt --keepalive-sec 300 (host only)
//        --log-dir /workspace/online-qa  --linger-sec 30 (wait after the match before deleting its data)
// Exit codes: 0 match finished · 2 lobby abandoned/room gone · 3 timeout · 4 left on purpose
//             1 error · 130 Ctrl-C/SIGTERM (leaves the room + deletes its data first)
import { mkdirSync, appendFileSync, writeFileSync, readFileSync } from "node:fs";
import { initializeApp, deleteApp } from "firebase/app";
import { getAuth, signInAnonymously } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore, doc, onSnapshot, getDocFromServer, terminate } from "firebase/firestore";

// ---------- args / config ----------
const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d; };
const MODE = flag("--host") ? "host" : flag("--join") ? "join" : null;
if (!MODE) { console.error("usage: seat-bot.mjs --host | --join CODE [--timeout-min 90] [--leave-after-turns N]"); process.exit(1); }
const JOIN_CODE = MODE === "join" ? String(opt("--join", "")).toUpperCase() : null;
const NAME = opt("--name", "Box Tester");
const CLAIM = +opt("--claim", 100);
const ANTE = +opt("--ante", 10), SEATS = +opt("--seats", 2), BOTS = +opt("--bots", 0);
const TIMEOUT_MS = +opt("--timeout-min", 90) * 60_000;
const LEAVE_AFTER = flag("--leave-after-turns") ? +opt("--leave-after-turns") : null;
const [PACE_MIN, PACE_MAX] = String(opt("--pace", "2000-4000")).split("-").map(Number);
const LOG_DIR = opt("--log-dir", "/workspace/online-qa");
const CODE_FILE = opt("--code-file", `${LOG_DIR}/seatbot-current-code.txt`);
const REGION = process.env.REGION ?? "us-central1";
const LINGER_MS = +opt("--linger-sec", 30) * 1000; // after match end, before deleteOnlineData
const KEEPALIVE_MS = +opt("--keepalive-sec", 300) * 1000; // host lobby heartbeat (keepLobby)

function loadConfig() {
  const e = process.env;
  if (e.FIREBASE_WEB_CONFIG) return JSON.parse(readFileSync(e.FIREBASE_WEB_CONFIG, "utf8"));
  if (e.GOOGLE_SERVICES_JSON) {
    const g = JSON.parse(readFileSync(e.GOOGLE_SERVICES_JSON, "utf8"));
    const c = g.client[0];
    return { apiKey: c.api_key[0].current_key, projectId: g.project_info.project_id,
      appId: c.client_info.mobilesdk_app_id, messagingSenderId: g.project_info.project_number };
  }
  if (e.FIREBASE_API_KEY && e.FIREBASE_PROJECT_ID) return { apiKey: e.FIREBASE_API_KEY, projectId: e.FIREBASE_PROJECT_ID, appId: e.FIREBASE_APP_ID };
  throw new Error("Set FIREBASE_WEB_CONFIG, GOOGLE_SERVICES_JSON, or FIREBASE_API_KEY + FIREBASE_PROJECT_ID");
}

// ---------- logging ----------
const pad = (n, w = 2) => String(n).padStart(w, "0");
function ts(d = new Date()) {
  const off = -d.getTimezoneOffset(), sign = off >= 0 ? "+" : "-";
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}${sign}${pad(Math.floor(Math.abs(off) / 60))}:${pad(Math.abs(off) % 60)}`;
}
mkdirSync(LOG_DIR, { recursive: true });
const LOG = `${LOG_DIR}/seatbot-${ts().replace(/[:.]/g, "").replace(/[+-]\d{4}$/, "")}-${MODE}-${process.pid}.log`;
const log = (...a) => { const line = `${ts()} [${MODE}] ${a.join(" ")}`; console.log(line); appendFileSync(LOG, line + "\n"); };
const errText = (e) => `${e?.code ?? "error"}: ${e?.message ?? e}${e?.details ? " details=" + JSON.stringify(e.details) : ""}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pace = () => sleep(PACE_MIN + Math.random() * Math.max(0, PACE_MAX - PACE_MIN));

// ---------- client ----------
log(`log file: ${LOG}`);
const CONFIG = loadConfig();
const app = initializeApp(CONFIG, `seatbot-${process.pid}`);
const auth = getAuth(app), fns = getFunctions(app, REGION), db = getFirestore(app);
const call = async (name, data) => {
  try { const r = (await httpsCallable(fns, name)(data)).data; return r; }
  catch (e) { log(`CALLABLE ERROR ${name}(${JSON.stringify(data)}) -> ${errText(e)}`); throw e; }
};
let uid = null, roomId = null, code = null, room = null, unsub = null;
let deleted = false, exiting = false, myTurns = 0, startBanks = null, startPot = 0, gemsBefore = null;
let finalRoom = null, carriedOut = 0; // finished-state snapshot; banks taken off the table by mid-match leavers

async function myGems() {
  try { const s = await getDocFromServer(doc(db, "users", uid)); return s.exists() ? s.data().gems : null; }
  catch (e) { log(`read users/${uid.slice(0, 6)}… failed -> ${errText(e)}`); return null; }
}
const name = (s, i) => s?.displayName ?? `Seat ${i + 1}`;
const seatList = (seats) => seats.map((s, i) => `${i}:${s.kind}${s.uid ? `(${s.uid === uid ? "me" : s.uid.slice(0, 6)})` : ""}${s.displayName ? ` "${s.displayName}"` : ""}`).join(" | ");

async function cleanup(reason, codeOut) {
  if (exiting) return; exiting = true;
  log(`cleanup: ${reason}`);
  unsub?.();
  if (roomId && room && (room.status === "lobby" || room.status === "playing") && !deleted) {
    try { await call("leaveRoom", { roomId }); log("leaveRoom ok"); } catch { /* logged */ }
  }
  if (uid && !deleted) {
    try { const r = await call("deleteOnlineData", {}); deleted = true; log(`deleteOnlineData ok: ${JSON.stringify(r)}`); } catch { /* logged */ }
  }
  await terminate(db).catch(() => {}); await deleteApp(app).catch(() => {});
  log(`exit ${codeOut} — log: ${LOG}`);
  process.exit(codeOut);
}
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { log(`${sig} received`); cleanup(sig, 130); });

// ---------- play policy ----------
// Bank any scoring hand; otherwise hold a pair (not a pair of 1s: missing triple 1s costs 10) and reroll.
function holdFor(dice) {
  const n = {}; dice.forEach((v) => (n[v] = (n[v] ?? 0) + 1));
  const pair = Object.keys(n).map(Number).find((k) => n[k] === 2 && k !== 1);
  return pair ? dice.map((v, i) => (v === pair ? i : -1)).filter((i) => i >= 0) : [];
}

let acting = false, lastPayoutMsg = null, lastStatus = null, lastMembers = [], lastTurnKey = null;
const waiters = [];
const changed = () => new Promise((r) => waiters.push(r));

function onRoom(r) {
  const prev = room; room = r;
  if (!r) { log("ROOM GONE (deleted on the server)"); waiters.splice(0).forEach((w) => w()); return; }
  if (r.status !== lastStatus) { log(`status: ${lastStatus ?? "-"} -> ${r.status} (v${r.version})`); lastStatus = r.status; }
  const members = r.memberUids ?? [];
  for (const u of members) if (!lastMembers.includes(u) && u !== uid) log(`member joined: ${u.slice(0, 6)}… seats: ${seatList(r.seats)}`);
  for (const u of lastMembers) if (!members.includes(u) && u !== uid) log(`member left/deleted: ${u.slice(0, 6)}… seats: ${seatList(r.seats)}`);
  lastMembers = members;
  const m = r.match;
  if (m && prev?.match) m.seats.forEach((s, i) => {
    const p = prev.match.seats[i];
    if (p && !p.eliminated && s.eliminated && s.connected === false && s.uid && p.bank > 0 && s.bank === 0) {
      carriedOut += p.bank;
      log(`seat ${i} "${name(s, i)}" LEFT mid-match carrying their table bank ${p.bank} back to their online gems`);
    }
  });
  if (r.status === "finished" && !finalRoom) finalRoom = JSON.parse(JSON.stringify(r));
  if (m) {
    if (m.lastPayout?.message && m.lastPayout.message !== lastPayoutMsg) { lastPayoutMsg = m.lastPayout.message; log(`payout: ${lastPayoutMsg}`); }
    const t = m.turn;
    const key = t ? `${t.seat}/${t.setNumber}/${t.rollNumber}` : "none";
    if (key !== lastTurnKey) {
      lastTurnKey = key;
      if (t) log(`turn: seat ${t.seat} "${name(m.seats[t.seat], t.seat)}"${m.seats[t.seat]?.uid === uid ? " (me)" : ""} set ${t.setNumber} roll ${t.rollNumber}${t.rollNumber ? ` dice ${t.dice.join(",")} score ${t.score?.kind}` : ""} | pot ${m.pot} | banks ${m.seats.map((s) => s.kind === "open" ? "-" : `${s.bank}${s.eliminated ? "x" : ""}`).join("/")}`);
    }
    if (!startBanks && prev?.status !== "playing" && r.status === "playing") { startBanks = m.seats.map((s) => s.bank); startPot = m.pot; log(`MATCH STARTED: pot ${m.pot} (antes), banks ${startBanks.join("/")}, seats: ${seatList(m.seats)}`); }
  }
  waiters.splice(0).forEach((w) => w());
}

async function playMyTurn() {
  acting = true;
  try {
    myTurns++;
    log(`MY TURN #${myTurns}`);
    for (;;) {
      const m = room?.match, t = m?.turn;
      if (!room || room.status !== "playing" || !t || m.seats[t.seat]?.uid !== uid) break;
      await pace();
      const cur = room.match.turn;
      if (room.status !== "playing" || !cur || room.match.seats[cur.seat]?.uid !== uid) break;
      const v = room.version;
      try {
        if (cur.rollNumber > 0 && cur.score && cur.score.kind !== "none") {
          log(`action: KEEP ${cur.dice.join(",")} (${cur.score.kind})`);
          await call("submitKeep", { roomId, expectedVersion: v });
        } else {
          const keep = cur.rollNumber > 0 ? holdFor(cur.dice) : [];
          log(`action: ROLL${keep.length ? ` holding ${keep.map((i) => cur.dice[i]).join(",")}` : ""} (roll ${cur.rollNumber + 1}/3)`);
          await call("submitRoll", { roomId, expectedVersion: v, keep });
        }
      } catch (e) {
        if (e?.code === "functions/aborted") { log("stale version, waiting for fresh state"); }
        else if (e?.code === "functions/failed-precondition") { log("server says not actionable now, re-checking"); }
        else throw e;
      }
      // wait for the snapshot reflecting our write
      for (let k = 0; k < 40 && room && room.version === v; k++) await Promise.race([changed(), sleep(500)]);
      const nt = room?.match?.turn;
      if (!nt || nt.seat !== cur.seat || nt.setNumber !== cur.setNumber) {
        // set over (banked or busted). A win keeps the seat with a fresh set; that counts as the same turn.
        if (nt && room.match.seats[nt.seat]?.uid === uid && room.status === "playing") { log("won the set — rolling again (same turn)"); continue; }
        break;
      }
    }
  } finally { acting = false; }
}

async function reportEnd() {
  const fr = finalRoom ?? room, m = fr.match;
  log("=== MATCH END ===");
  log(`status ${fr.status}, winner seat ${m.winnerSeat} "${name(m.seats[m.winnerSeat], m.winnerSeat)}", pot ${m.pot}`);
  log(`settlement message: ${m.lastPayout?.message ?? "(none)"}`);
  m.seats.forEach((s, i) => {
    if (s.kind === "open") return;
    const who = s.uid === uid ? "me" : s.uid ? s.uid.slice(0, 6) + "…" : "left/anon";
    log(`seat ${i} ${s.kind} "${name(s, i)}" (${who}): table bank start ${startBanks?.[i] ?? "?"} -> final ${s.bank}${s.eliminated ? " (out)" : ""}`);
  });
  const after = await myGems();
  log(`my online gems: before ${gemsBefore} -> after ${after} (other players' users docs are not readable by rules; their start/final table banks above = their escrowed online balance before/after)`);
  const tot0 = startBanks ? startBanks.reduce((a, b) => a + b, 0) + startPot : null;
  const tot1 = m.seats.reduce((a, s) => a + (s.kind === "open" ? 0 : s.bank), 0) + m.pot;
  const end = tot1 + carriedOut;
  log(`gem check: table total at start (banks+pot) ${tot0 ?? "?"} -> at end ${tot1}${carriedOut ? ` + ${carriedOut} carried out by mid-match leavers = ${end}` : ""}${tot0 == null ? "" : tot0 === end ? " ✓ conserved" : " ✗ MISMATCH"}`);
  if (LINGER_MS > 0) { log(`lingering ${LINGER_MS / 1000}s so the other player can read the result before this seat's data is deleted`); await sleep(LINGER_MS); }
}

// ---------- main ----------
const deadline = Date.now() + TIMEOUT_MS;
try {
  log(`mode ${MODE}${JOIN_CODE ? " code " + JOIN_CODE : ""}, name "${NAME}", claim ${CLAIM}, project ${CONFIG.projectId}, timeout ${TIMEOUT_MS / 60000} min, leave-after-turns ${LEAVE_AFTER ?? "off"}, pace ${PACE_MIN}-${PACE_MAX} ms`);
  uid = (await signInAnonymously(auth)).user.uid;
  log(`signed in anonymously as ${uid.slice(0, 6)}…`);
  if (MODE === "host") {
    ({ roomId, code } = await call("createRoom", { seatCount: SEATS, botCount: BOTS, ante: ANTE, displayName: NAME, clientGemClaim: CLAIM }));
    writeFileSync(CODE_FILE, code + "\n");
    log(`ROOM CODE: ${code} (written to ${CODE_FILE}) room ${roomId}`);
    console.log(`\n   >>> ROOM CODE: ${code} <<<\n`);
  } else {
    ({ roomId } = await call("joinRoom", { code: JOIN_CODE, displayName: NAME, clientGemClaim: CLAIM }));
    code = JOIN_CODE;
    log(`joined room ${roomId} with code ${code}`);
  }
  gemsBefore = await myGems();
  log(`my online gems before: ${gemsBefore}`);
  unsub = onSnapshot(doc(db, "rooms", roomId), (s) => onRoom(s.exists() ? { id: s.id, ...s.data() } : null),
    (e) => { log(`room listener error -> ${errText(e)}`); onRoom(null); });

  let lastKeep = Date.now(), keepWarned = false, started = false;
  while (true) {
    await Promise.race([changed(), sleep(1000)]);
    if (Date.now() > deadline) { log(`TIMEOUT after ${TIMEOUT_MS / 60000} min`); await cleanup("timeout", 3); }
    if (!room) {
      if (exiting) continue;
      log("Room no longer exists (deleted). Not creating a new code."); await cleanup("room gone", 2);
    }
    if (room.status === "abandoned") {
      log(`LOBBY ABANDONED: the server marked room code ${code} abandoned (host left or 30-min idle sweep). This code is dead — rerun seat-bot for a new one; NOT creating a new code automatically.`);
      await cleanup("abandoned", 2);
    }
    if (room.status === "lobby") {
      const others = room.seats.filter((s) => s.uid && s.uid !== uid && (s.kind === "human" || s.kind === "host"));
      if (MODE === "host" && others.length >= 1 && !started) {
        log(`human joined (${others.map((s) => `"${s.displayName}"`).join(", ")}); starting match shortly`);
        await pace();
        try { await call("startMatch", { roomId }); started = true; log("startMatch ok"); } catch { await sleep(3000); }
      }
      if (MODE === "host" && Date.now() - lastKeep > KEEPALIVE_MS) {
        lastKeep = Date.now();
        try { await call("keepLobby", { roomId }); log("lobby heartbeat (keepLobby) ok"); }
        catch (e) { if (!keepWarned) { keepWarned = true; log("WARNING: keepLobby unavailable on this backend — the server abandons idle lobbies after 30 min, so this code expires ~30 min after creation/last join."); } }
      }
      continue;
    }
    if (room.status === "playing") {
      const t = room.match?.turn;
      if (LEAVE_AFTER != null && myTurns >= LEAVE_AFTER && !acting && !(t && room.match.seats[t.seat]?.uid === uid)) {
        log(`LEAVING at turn ${myTurns} (--leave-after-turns ${LEAVE_AFTER}); my bank ${room.match.seats.find((s) => s.uid === uid)?.bank}, pot ${room.match.pot}`);
        try { await call("leaveRoom", { roomId }); log("leaveRoom ok (mid-match)"); } catch { /* logged */ }
        await sleep(1500);
        log(`after leave: status ${room?.status}, payout ${room?.match?.lastPayout?.message ?? "-"}`);
        log(`my online gems after leaving: ${await myGems()}`);
        room = { ...room, status: "left" };
        await cleanup("left on purpose", 4);
      }
      if (!acting && t && room.match.seats[t.seat]?.uid === uid) await playMyTurn();
      continue;
    }
    if (room.status === "finished") { await reportEnd(); await cleanup("match finished", 0); }
  }
} catch (e) {
  log(`FATAL ${errText(e)}`);
  await cleanup("error", 1);
}

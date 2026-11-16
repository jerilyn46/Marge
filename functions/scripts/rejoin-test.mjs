// Live cold-restart rejoin check against marge-online (Firebase JS client SDK,
// anonymous auth, no secrets in this file). Needs a seat-bot host running:
//   node seat-bot.mjs --host --claim 40 &      # writes the code file
//   GOOGLE_SERVICES_JSON=... node rejoin-test.mjs [--code ABC234]
// The client joins, plays one turn, then "cold restarts": drops its listener,
// Firestore and app instance, keeps only its signed-in user (as FirebaseAuth
// persists it on a phone), runs the app's active-room query
// (rooms where memberUids array-contains uid, live status picked client-side
// like lib/online/active_room.dart), resubscribes and plays to the end.
// Exit 0 = PASS.
import { readFileSync } from "node:fs";
import { initializeApp, deleteApp } from "firebase/app";
import { getAuth, signInAnonymously, updateCurrentUser } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore, doc, getDocFromServer, onSnapshot, terminate, collection, query, where, getDocs } from "firebase/firestore";

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const CODE_FILE = opt("--code-file", "/workspace/online-qa/seatbot-current-code.txt");
const REGION = process.env.REGION ?? "us-central1";
const g = JSON.parse(readFileSync(process.env.GOOGLE_SERVICES_JSON, "utf8"));
const c0 = g.client[0];
const CONFIG = { apiKey: c0.api_key[0].current_key, projectId: g.project_info.project_id,
  appId: c0.client_info.mobilesdk_app_id, messagingSenderId: g.project_info.project_number };
const t0 = Date.now();
const log = (...a) => console.log(`+${((Date.now() - t0) / 1000).toFixed(1)}s`, ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let fails = 0;
const check = (ok, what) => { log(`${ok ? "PASS" : "FAIL"} ${what}`); if (!ok) fails++; };

// Port of lib/online/active_room.dart pickActiveRoom.
function pickActiveRoom(rooms, uid) {
  const live = (r) => r.status === "playing"
    ? !!r.match && r.match.status !== "finished" && r.match.seats.some((s) => s.uid === uid && !s.eliminated)
    : r.status === "lobby" && r.seats.some((s) => s.uid === uid);
  return rooms.filter(live).sort((a, b) => (b.status === "playing") - (a.status === "playing") || b.version - a.version)[0] ?? null;
}

function makeClient(name) {
  const app = initializeApp(CONFIG, name);
  return { app, auth: getAuth(app), db: getFirestore(app), fns: getFunctions(app, REGION) };
}
const call = (cl, n, d) => httpsCallable(cl.fns, n)(d).then((r) => r.data);

/** Follow the room and play my turns. stopAfterTurns: return after N of my turns end. */
async function play(cl, roomId, uid, { stopAfterTurns = Infinity } = {}) {
  let room = null, wake = null, turns = 0, acting = false;
  const unsub = onSnapshot(doc(cl.db, "rooms", roomId), (s) => { room = s.exists() ? s.data() : null; wake?.(); },
    (e) => log("listener error", e.code));
  const changed = () => new Promise((r) => { wake = r; setTimeout(r, 1500); });
  const deadline = Date.now() + 15 * 60_000;
  try {
    while (Date.now() < deadline) {
      await changed();
      if (!room) { const s = await getDocFromServer(doc(cl.db, "rooms", roomId)); room = s.exists() ? s.data() : null; }
      if (!room || room.status === "finished" || room.status === "abandoned") return { room, turns };
      const m = room.match, t = m?.turn;
      if (room.status !== "playing" || !t || m.seats[t.seat]?.uid !== uid || acting) continue;
      acting = true;
      const startSet = `${t.setNumber}`;
      try {
        // one action per loop: bank any score, else roll (hold a non-1 pair)
        await sleep(600);
        if (t.rollNumber > 0 && t.score && t.score.kind !== "none") await call(cl, "submitKeep", { roomId, expectedVersion: room.version });
        else {
          const n = {}; t.dice.forEach((v) => (n[v] = (n[v] ?? 0) + 1));
          const pair = t.rollNumber > 0 ? Object.keys(n).map(Number).find((k) => n[k] === 2 && k !== 1) : undefined;
          await call(cl, "submitRoll", { roomId, expectedVersion: room.version, keep: pair ? t.dice.map((v, i) => (v === pair ? i : -1)).filter((i) => i >= 0) : [] });
        }
      } catch (e) {
        log(`action error ${e.code} — re-reading`);
        const s = await getDocFromServer(doc(cl.db, "rooms", roomId)); room = s.exists() ? s.data() : null;
      } finally { acting = false; }
      for (let k = 0; k < 20; k++) {
        const nt = room?.match?.turn;
        if (!nt || room.status !== "playing" || room.match.seats[nt.seat]?.uid !== uid) { turns++; log(`my turn #${turns} done; pot ${room?.match?.pot}`); break; }
        if (`${nt.setNumber}` !== startSet || nt.rollNumber !== t.rollNumber) break;
        await changed();
      }
      if (turns >= stopAfterTurns) return { room, turns };
    }
    throw new Error("timeout");
  } finally { unsub(); }
}

const code = opt("--code") ?? readFileSync(CODE_FILE, "utf8").trim();
log(`joining ${code}`);
const a = makeClient("phone-boot-1");
const uid = (await signInAnonymously(a.auth)).user.uid;
const { roomId } = await call(a, "joinRoom", { code, displayName: "Rejoin Tester", clientGemClaim: 40 });
log(`joined room ${roomId} as ${uid.slice(0, 6)}…`);
const first = await play(a, roomId, uid, { stopAfterTurns: 1 });
check(first.room?.status === "playing" && first.turns === 1, `played 1 turn, match still running (status ${first.room?.status})`);

// ---- cold restart: throw away listener, Firestore, app; keep only the persisted user ----
log("COLD RESTART: discarding app state");
const b = makeClient("phone-boot-2");
await updateCurrentUser(b.auth, a.auth.currentUser); // what FirebaseAuth persistence gives a relaunched app
await terminate(a.db); await deleteApp(a.app);
await sleep(4000); // app was closed for a moment
check(b.auth.currentUser?.uid === uid, "same anonymous uid after restart");
const q = await getDocs(query(collection(b.db, "rooms"), where("memberUids", "array-contains", uid)));
const rooms = q.docs.map((d) => ({ id: d.id, ...d.data() }));
const live = pickActiveRoom(rooms, uid);
check(live?.id === roomId, `active-room query found the match (${q.size} member room(s), live=${live?.id ?? "none"}, status ${live?.status})`);

const end = await play(b, roomId, uid);
const m = end.room?.match;
check(end.room?.status === "finished", `resubscribed and played to the end (${end.turns} more turns), winner seat ${m?.winnerSeat}`);
if (m) {
  const startTotal = (m.startBanks ?? []).reduce((x, y) => x + y, 0);
  const endTotal = m.seats.reduce((x, s) => x + (s.kind === "open" ? 0 : s.bank), 0) + m.pot;
  check(m.startBanks && startTotal === endTotal, `gems conserved: start ${startTotal} -> end ${endTotal} (banks ${m.seats.map((s) => s.bank).join("/")}, pot ${m.pot})`);
  const me = m.seats.find((s) => s.uid === uid);
  const u = await getDocFromServer(doc(b.db, "users", uid));
  check(u.data()?.gems === me.bank && !u.data()?.escrowRoom, `my online gems ${u.data()?.gems} == final table bank ${me.bank}, escrow cleared`);
}
const after = await getDocs(query(collection(b.db, "rooms"), where("memberUids", "array-contains", uid)));
check(pickActiveRoom(after.docs.map((d) => ({ id: d.id, ...d.data() })), uid) === null, "no 'Rejoin your match' after the match ended");
await sleep(12000); // let the host bot read the result first
try { await call(b, "deleteOnlineData", {}); log("cleanup: deleteOnlineData ok"); } catch (e) { log("cleanup failed", e.code); }
await terminate(b.db).catch(() => {}); await deleteApp(b.app).catch(() => {});
log(fails ? `REJOIN TEST FAILED (${fails})` : "REJOIN TEST PASS");
process.exit(fails ? 1 : 0);

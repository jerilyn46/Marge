// Two-client smoke against a LIVE Firebase project (default marge-online).
// Uses the Firebase JS client SDK with independent anonymous users, each in its
// own app instance, so Firestore rules and callables are exercised exactly as a
// phone would. No secrets in this file: config comes from env.
//
//   cd functions/scripts && npm install
//   GOOGLE_SERVICES_JSON=/path/to/google-services.json RUNS=3 node live-smoke.mjs
//     or FIREBASE_WEB_CONFIG=/path/to/web-config.json (firebase_get_sdk_config output)
//     or FIREBASE_API_KEY=... FIREBASE_PROJECT_ID=... [FIREBASE_APP_ID=...]
//   Optional: REGION (us-central1), RUNS (1), MAX_TURNS (200).
//
// Every test user is removed at the end via deleteOnlineData (also on failure).
// Room docs stay behind as scrubbed husks (no client/server delete path exists).
import { readFileSync } from "node:fs";
import { initializeApp, deleteApp } from "firebase/app";
import { getAuth, signInAnonymously } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore, doc, getDocFromServer, onSnapshot, terminate } from "firebase/firestore";

function loadConfig() {
  const e = process.env;
  if (e.FIREBASE_WEB_CONFIG) return JSON.parse(readFileSync(e.FIREBASE_WEB_CONFIG, "utf8"));
  if (e.GOOGLE_SERVICES_JSON) {
    const g = JSON.parse(readFileSync(e.GOOGLE_SERVICES_JSON, "utf8"));
    const c = g.client[0];
    return { apiKey: c.api_key[0].current_key, projectId: g.project_info.project_id,
      appId: c.client_info.mobilesdk_app_id, messagingSenderId: g.project_info.project_number };
  }
  if (e.FIREBASE_API_KEY && e.FIREBASE_PROJECT_ID) {
    return { apiKey: e.FIREBASE_API_KEY, projectId: e.FIREBASE_PROJECT_ID, appId: e.FIREBASE_APP_ID };
  }
  throw new Error("Set FIREBASE_WEB_CONFIG, GOOGLE_SERVICES_JSON, or FIREBASE_API_KEY + FIREBASE_PROJECT_ID");
}
const CONFIG = loadConfig();
const REGION = process.env.REGION ?? "us-central1";
const RUNS = +(process.env.RUNS ?? 1);
const MAX_TURNS = +(process.env.MAX_TURNS ?? 200);
const tag = Math.random().toString(36).slice(2, 6);

let fails = 0, results = [];
const ok = (c, msg) => { console.log(`${c ? "PASS" : "FAIL"} ${msg}`); results.push([!!c, msg]); if (!c) fails++; return !!c; };
const errText = (e) => `${e?.code ?? "?"}: ${e?.message ?? e}`;
const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let seq = 0;
async function client(label) {
  const app = initializeApp(CONFIG, `qa-${label}-${tag}-${seq++}`);
  const auth = getAuth(app);
  const cred = await signInAnonymously(auth);
  const fns = getFunctions(app, REGION), db = getFirestore(app);
  const c = { label, app, auth, db, uid: cred.user.uid, deleted: false, unsubs: [] };
  c.call = async (name, data) => (await httpsCallable(fns, name)(data)).data;
  // minVersion: wait out watch-stream lag (a live listener can serve a slightly stale server read).
  c.room = async (id, minVersion = -1) => {
    for (let i = 0; ; i++) {
      const s = await getDocFromServer(doc(db, "rooms", id));
      const r = s.exists() ? { id, ...s.data() } : null;
      if (!r || r.version >= minVersion || i >= 40) return r;
      await sleep(250);
    }
  };
  c.user = async () => { const s = await getDocFromServer(doc(db, "users", c.uid)); return s.exists() ? s.data() : null; };
  return c;
}
async function expectErr(p, code, label) {
  try { await p; return ok(false, `${label} (expected ${code}, call succeeded)`); }
  catch (e) { return ok(e.code === code, `${label} -> ${errText(e)}`); }
}
const pairKeep = (dice) => {
  const n = {}; dice.forEach((v) => (n[v] = (n[v] ?? 0) + 1));
  const p = Object.keys(n).find((k) => n[k] === 2);
  return p ? dice.map((v, i) => (v === +p ? i : -1)).filter((i) => i >= 0) : [];
};

/** One scoring set for the seat whose turn it is: roll up to 3x, bank any hit. */
async function playSet(byUid, r) {
  const seat = r.match.turn.seat, set = r.match.turn.setNumber, cl = byUid[r.match.seats[seat].uid];
  if (!cl) throw new Error(`no client for seat ${seat}`);
  for (let k = 0; k < 3; k++) {
    const t = r.match.turn;
    await cl.call("submitRoll", { roomId: r.id, expectedVersion: r.version, keep: t.rollNumber > 0 ? pairKeep(t.dice) : [] });
    r = await cl.room(r.id, r.version + 1);
    const nt = r.match?.turn;
    if (r.status !== "playing" || !nt || nt.seat !== seat || nt.setNumber !== set) return r;
    if (nt.score && nt.score.kind !== "none") { await cl.call("submitKeep", { roomId: r.id, expectedVersion: r.version }); return cl.room(r.id, r.version + 1); }
  }
  return r;
}
const tableTotal = (r) => sum(r.match.seats.filter((s) => s.kind !== "open").map((s) => s.bank)) + r.match.pot;

async function scenarioFullMatch(A, B) {
  console.log("-- Scenario A: 2 humans, create/join/wrong code/start/full match");
  const claimA = 40, claimB = 30, ante = 10, total = claimA + claimB;
  const { roomId, code } = await A.call("createRoom", { seatCount: 2, botCount: 0, ante, displayName: `QA Host ${tag}`, clientGemClaim: claimA });
  ok(/^[A-HJ-NP-Z2-9]{6}$/.test(code), `createRoom -> code ${code}`);
  // Host listens live, like the lobby screen does.
  let sawGuest = false;
  const unsub = onSnapshot(doc(A.db, "rooms", roomId), (s) => { if (s.data()?.memberUids?.includes(B.uid)) sawGuest = true; }, () => {});
  A.unsubs.push(unsub);
  await expectErr(B.call("joinRoom", { code: code === "ZZZZZZ" ? "YYYYYY" : "ZZZZZZ", displayName: `QA Guest ${tag}`, clientGemClaim: claimB }), "functions/not-found", "wrong code rejected");
  await expectErr(B.room(roomId), "permission-denied", "non-member cannot read room (rules)");
  ok((await B.call("joinRoom", { code: code.toLowerCase(), displayName: `QA Guest ${tag}`, clientGemClaim: claimB })).roomId === roomId, "joinRoom by code (lowercase input) -> same roomId");
  const [ra, rb] = [await A.room(roomId, 1), await B.room(roomId, 1)];
  const both = (r) => r && r.memberUids.includes(A.uid) && r.memberUids.includes(B.uid) && r.seats.filter((s) => s.uid).length === 2;
  ok(both(ra) && both(rb) && ra.version === rb.version, `both clients see both members (v${ra?.version}/${rb?.version}, seats: ${ra?.seats.map((s) => s.displayName ?? s.kind).join(", ")})`);
  for (let i = 0; i < 20 && !sawGuest; i++) await sleep(250);
  ok(sawGuest, "host realtime listener saw guest join");
  await expectErr(B.call("startMatch", { roomId }), "functions/permission-denied", "non-host startMatch rejected");
  const vLobby = ra.version;
  await A.call("startMatch", { roomId });
  let r = await A.room(roomId, vLobby + 1);
  const [ua, ub] = [await A.user(), await B.user()];
  ok(r.status === "playing" && r.match.pot === 2 * ante && r.match.seats[0].bank === claimA - ante && r.match.seats[1].bank === claimB - ante,
    `startMatch: playing, pot ${r.match.pot}, banks ${r.match.seats.map((s) => s.bank)}`);
  ok(ua?.gems === 0 && ub?.gems === 0 && ua?.escrowRoom === roomId && ub?.escrowRoom === roomId, `escrow: users gems ${ua?.gems}/${ub?.gems}, escrowRoom set`);
  await expectErr(A.call("joinRoom", { code }), "functions/not-found", "code freed after start");
  const byUid = { [A.uid]: A, [B.uid]: B };
  const turnsBy = { 0: 0, 1: 0 }; let badTotal = null, staleOk = null, turns = 0;
  // Stale-version write must be refused.
  try { await byUid[r.match.seats[r.match.turn.seat].uid].call("submitRoll", { roomId, expectedVersion: r.version - 1 }); staleOk = "accepted"; }
  catch (e) { staleOk = errText(e); }
  ok(staleOk.startsWith("functions/aborted"), `stale expectedVersion rejected -> ${staleOk}`);
  const wrong = byUid[r.match.seats[1 - r.match.turn.seat].uid];
  await expectErr(wrong.call("submitRoll", { roomId, expectedVersion: r.version }), "functions/failed-precondition", "out-of-turn roll rejected");
  r = await A.room(roomId, r.version);
  while (r.status === "playing" && turns < MAX_TURNS) {
    turnsBy[r.match.turn.seat]++; turns++;
    r = await playSet(byUid, r);
    if (r.status === "playing" && tableTotal(r) !== total && badTotal === null) badTotal = `turn ${turns}: banks ${r.match.seats.map((s) => s.bank)} pot ${r.match.pot}`;
  }
  const rb2 = await B.room(roomId, r.version);
  ok(rb2.version === r.version && rb2.status === r.status, `both clients agree on final state (v${r.version})`);
  ok(badTotal === null, `gems conserved every turn (banks+pot=${total})${badTotal ? " broke at " + badTotal : ""}`);
  ok(turnsBy[0] > 0 && turnsBy[1] > 0, `turns alternated: seat0 ${turnsBy[0]} sets, seat1 ${turnsBy[1]} sets`);
  let endedBy = "dice";
  if (r.status === "playing") { endedBy = "host endMatch (MAX_TURNS)"; await A.call("endMatch", { roomId }); r = await A.room(roomId, r.version + 1); }
  const [fa, fb] = [await A.user(), await B.user()];
  const fin = r.match.seats;
  ok(r.status === "finished" && r.match.winnerSeat != null, `match finished by ${endedBy} after ${turns} sets, winner seat ${r.match.winnerSeat}: ${r.match.lastPayout?.message ?? ""}`);
  ok(fa.gems === fin[0].bank && fb.gems === fin[1].bank && fa.escrowRoom === null && fb.escrowRoom === null,
    `settle: users gems ${fa.gems}/${fb.gems} == final banks ${fin[0].bank}/${fin[1].bank}, escrow cleared`);
  ok(fa.gems + fb.gems + r.match.pot === total, `end total ${fa.gems}+${fb.gems}+pot ${r.match.pot} = ${total}`);
}

async function scenarioLeave(C, D) {
  console.log("-- Scenario B: 2 humans + 1 bot, guest leaves mid-match");
  const claim = 100, ante = 10, total = 2 * claim + 100;
  const { roomId, code } = await C.call("createRoom", { seatCount: 3, botCount: 1, ante, displayName: `QA Host2 ${tag}`, clientGemClaim: claim });
  await D.call("joinRoom", { code, displayName: `QA Guest2 ${tag}`, clientGemClaim: claim });
  await C.call("startMatch", { roomId });
  const byUid = { [C.uid]: C, [D.uid]: D };
  let r = await C.room(roomId, 2);
  for (let k = 0; k < 2 && r.status === "playing"; k++) r = await playSet(byUid, r);
  if (!ok(r.status === "playing", `match still playing after 2 sets (status ${r.status})`)) return;
  const dSeat = r.match.seats.findIndex((s) => s.uid === D.uid), dBank = r.match.seats[dSeat].bank;
  await D.call("leaveRoom", { roomId });
  r = await C.room(roomId, r.version + 1);
  const ud = await D.user();
  ok(r.status === "playing" && r.match.seats[dSeat].eliminated && r.match.turn && r.match.turn.seat !== dSeat,
    `after leave: status ${r.status}, guest seat eliminated, turn on seat ${r.match.turn?.seat}`);
  ok(ud.gems === dBank && ud.escrowRoom === null, `leaver keeps table bank: users gems ${ud.gems} == bank ${dBank}, escrow cleared`);
  ok(tableTotal(r) + ud.gems === total, `conserved after leave: table ${tableTotal(r)} + leaver ${ud.gems} = ${total}`);
  const v0 = r.version;
  r = await playSet(byUid, r);
  ok(r.version > v0, `remaining host took a turn after leave (v${v0}->v${r.version}, status ${r.status})`);
  let turns = 0;
  while (r.status === "playing" && turns++ < MAX_TURNS) r = await playSet(byUid, r);
  if (r.status === "playing") { await C.call("endMatch", { roomId }); r = await C.room(roomId, r.version + 1); }
  const uc = await C.user();
  const cSeat = r.match.seats.findIndex((s) => s.uid === C.uid);
  ok(r.status === "finished" && uc.gems === r.match.seats[cSeat].bank && uc.escrowRoom === null,
    `host settles: finished, users gems ${uc.gems} == bank ${r.match.seats[cSeat].bank} (bot ${r.match.seats.find((s) => s.kind === "bot").bank}, pot ${r.match.pot})`);
}

async function cleanup(clients) {
  for (const c of clients) {
    c.unsubs.forEach((u) => u());
    if (c.deleted) continue;
    try {
      const res = await c.call("deleteOnlineData", {});
      c.deleted = true;
      let gone = "token still valid";
      try { await c.auth.currentUser.getIdToken(true); } catch (e) { gone = e.code; }
      ok(res.ok && gone !== "token still valid", `deleteOnlineData ${c.label}: roomsScrubbed ${res.roomsScrubbed}, auth user gone (${gone})`);
    } catch (e) { ok(false, `deleteOnlineData ${c.label} -> ${errText(e)}`); }
  }
  for (const c of clients) { await terminate(c.db).catch(() => {}); await deleteApp(c.app).catch(() => {}); }
}

const summary = [];
for (let run = 1; run <= RUNS; run++) {
  console.log(`=== LIVE RUN ${run}/${RUNS} project ${CONFIG.projectId} region ${REGION}`);
  const before = fails; results = [];
  const clients = [];
  try {
    const A = await client("A"), B = await client("B"); clients.push(A, B);
    ok(A.uid !== B.uid, "two independent anonymous users (separate app instances)");
    await scenarioFullMatch(A, B);
    const C = await client("C"), D = await client("D"); clients.push(C, D);
    await scenarioLeave(C, D);
  } catch (e) { ok(false, `unexpected error: ${errText(e)}`); }
  await cleanup(clients);
  summary.push(`run ${run}: ${results.filter((x) => x[0]).length}/${results.length} PASS`);
  console.log(fails === before ? `RUN ${run} OK` : `RUN ${run} FAILED (${fails - before})`);
}
console.log(summary.join("\n"));
console.log(fails ? `LIVE SMOKE FAILED (${fails})` : "LIVE SMOKE OK");
process.exit(fails ? 1 : 0);

/**
 * Marge invite-room multiplayer — Cloud Functions (callable, v2).
 * Server is authoritative for deck/dice, ante, pot and payouts.
 * Rules live in ./engine.ts (port of lib/engine). See docs/multiplayer-invite-mvp.md.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { randomInt } from "node:crypto";
import {
  autoPlayTimedOut, bank, BOT_START_BANK, MatchState, newMatch, roll, Rng, RuleError, runBots, SeatState,
} from "./engine";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });

const STARTING_GEMS = 100;
const MAX_CLIENT_CLAIM = 5000; // MVP cap on first-auth seed (honesty risk)
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function uidOf(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first");
  return req.auth.uid;
}

function seatLabel(name: unknown, uid: string): string {
  const n = typeof name === "string" ? name.trim().slice(0, 20) : "";
  return n || `Player ${uid.slice(0, 4).toUpperCase()}`;
}

function newCode(): string {
  let s = "";
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return s;
}

/** Seed users/{uid} once from the client claim (clamped), then server-owned. */
async function ensureUser(tx: Transaction, uid: string, name: unknown, claim: unknown) {
  const ref = db.collection("users").doc(uid);
  const snap = await tx.get(ref);
  if (!snap.exists) {
    const c = typeof claim === "number" && claim >= 0 ? Math.min(Math.floor(claim), MAX_CLIENT_CLAIM) : STARTING_GEMS;
    tx.set(ref, {
      gems: c, seededFromClaim: c, displayName: seatLabel(name, uid),
      createdAt: FieldValue.serverTimestamp(),
    });
    return c;
  }
  tx.update(ref, { displayName: seatLabel(name, uid) });
  return (snap.data()!.gems as number) ?? 0;
}

export const createRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const { seatCount = 4, botCount = 0, ante = 10, displayName, clientGemClaim } = req.data ?? {};
  if (seatCount < 2 || seatCount > 8 || botCount < 0 || botCount >= seatCount) {
    throw new HttpsError("invalid-argument", "Bad seat/bot counts");
  }
  const roomRef = db.collection("rooms").doc();
  // TODO: retry on code collision against roomCodes/{code}.
  const code = newCode();
  await db.runTransaction(async (tx) => {
    const codeRef = db.collection("roomCodes").doc(code);
    if ((await tx.get(codeRef)).exists) throw new HttpsError("aborted", "Code collision, retry");
    const gems = await ensureUser(tx, uid, displayName, clientGemClaim);
    if (gems < ante) throw new HttpsError("failed-precondition", "Not enough online gems");
    const seats = Array.from({ length: seatCount }, (_, i) => {
      if (i === 0) return { index: 0, kind: "host", uid, displayName: seatLabel(displayName, uid), connected: true };
      // Bots only in leftover seats the host configured (last botCount seats).
      if (i >= seatCount - botCount) return { index: i, kind: "bot", displayName: `Bot ${i}`, connected: true };
      return { index: i, kind: "open" };
    });
    tx.set(codeRef, { roomId: roomRef.id, createdAt: FieldValue.serverTimestamp() });
    tx.set(roomRef, {
      code, hostUid: uid, status: "lobby", ante, pot: 0, seats, memberUids: [uid],
      version: 0, createdAt: FieldValue.serverTimestamp(), lastActivity: FieldValue.serverTimestamp(),
    });
  });
  return { roomId: roomRef.id, code };
});

export const joinRoom = onCall(async (req) => {
  const uid = uidOf(req);
  const code = String(req.data?.code ?? "").toUpperCase();
  const codeSnap = await db.collection("roomCodes").doc(code).get();
  if (!codeSnap.exists) throw new HttpsError("not-found", "No room with that code");
  const roomId = codeSnap.data()!.roomId as string;
  await db.runTransaction(async (tx) => {
    const ref = db.collection("rooms").doc(roomId);
    const room = (await tx.get(ref)).data();
    if (!room || room.status !== "lobby") throw new HttpsError("failed-precondition", "Room not open");
    const gems = await ensureUser(tx, uid, req.data?.displayName, req.data?.clientGemClaim);
    if (gems < room.ante) throw new HttpsError("failed-precondition", "Not enough online gems");
    const seats = room.seats as Array<Record<string, unknown>>;
    if (seats.some((s) => s.uid === uid)) return; // rejoin
    const open = seats.find((s) => s.kind === "open");
    if (!open) throw new HttpsError("resource-exhausted", "Room full");
    Object.assign(open, { kind: "human", uid, displayName: seatLabel(req.data?.displayName, uid), connected: true });
    tx.update(ref, { seats, memberUids: FieldValue.arrayUnion(uid), version: FieldValue.increment(1),
      lastActivity: FieldValue.serverTimestamp() });
  });
  return { roomId };
});

const TURN_TIMEOUT_MS = 60_000;
const LOBBY_IDLE_MS = 30 * 60_000;
const rng: Rng = () => randomInt(0, 1_000_000) / 1_000_000;

type Seat = Record<string, any>;

function asRuleError(e: unknown): never {
  if (e instanceof RuleError) throw new HttpsError("failed-precondition", e.message);
  throw e;
}

/** Return each human seat's table bank to users/{uid}.gems (escrow release). */
function settle(tx: Transaction, m: MatchState) {
  for (const s of m.seats) {
    if (s.uid && (s.kind === "host" || s.kind === "human")) {
      tx.set(db.collection("users").doc(s.uid), { gems: FieldValue.increment(s.bank), escrowRoom: null }, { merge: true });
      s.bank = 0;
    }
  }
}

/** Shared write after any match mutation: bots, settle on finish, version bump. */
function commitMatch(tx: Transaction, ref: FirebaseFirestore.DocumentReference, m: MatchState) {
  runBots(m, rng);
  const finished = m.status === "finished";
  const display = JSON.parse(JSON.stringify(m)) as MatchState; // banks before settle
  if (finished) settle(tx, m);
  tx.update(ref, {
    match: display, pot: display.pot, turnSeat: display.turn?.seat ?? null,
    status: finished ? "finished" : "playing", version: FieldValue.increment(1),
    turnDeadline: finished ? null : Date.now() + TURN_TIMEOUT_MS,
    lastActivity: FieldValue.serverTimestamp(),
  });
}

async function withRoom<T>(roomId: string, fn: (tx: Transaction, ref: FirebaseFirestore.DocumentReference, room: Record<string, any>) => Promise<T>) {
  return db.runTransaction(async (tx) => {
    const ref = db.collection("rooms").doc(String(roomId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Room not found");
    return fn(tx, ref, snap.data()!);
  });
}

function mySeat(room: Record<string, any>, uid: string): number {
  const m = room.match as MatchState | undefined;
  const seats: Seat[] = m?.seats ?? room.seats;
  const i = seats.findIndex((s) => s.uid === uid);
  if (i < 0) throw new HttpsError("permission-denied", "Not seated in this room");
  return i;
}

function checkVersion(room: Record<string, any>, expected: unknown) {
  if (typeof expected === "number" && expected !== room.version) {
    throw new HttpsError("aborted", "Stale state — refresh and retry");
  }
}

/** Mark seat out of the match; advance turn or finish so others can keep playing. */
function dropSeat(m: MatchState, i: number) {
  const s = m.seats[i];
  s.eliminated = true;
  s.connected = false;
  if (m.turn?.seat === i) m.turn = null;
  const live = m.seats.filter((x) => x.kind !== "open" && !x.eliminated);
  if (live.length <= 1) { m.status = "finished"; m.winnerSeat = live[0]?.index ?? null; m.turn = null; return; }
  if (!m.turn) {
    let n = (i + 1) % m.seats.length;
    while (m.seats[n].kind === "open" || m.seats[n].eliminated) n = (n + 1) % m.seats.length;
    m.turn = { seat: n, rollNumber: 0, setNumber: 1, dice: [1, 1, 1], kept: [false, false, false], carried: null, score: null };
  }
}

export const leaveRoom = onCall(async (req) => {
  const uid = uidOf(req);
  await withRoom(req.data?.roomId, async (tx, ref, room) => {
    const i = mySeat(room, uid);
    if (room.status === "lobby") {
      if (room.hostUid === uid) {
        tx.update(ref, { status: "abandoned", lastActivity: FieldValue.serverTimestamp() });
        tx.delete(db.collection("roomCodes").doc(room.code));
        return;
      }
      const seats = room.seats as Seat[];
      seats[i] = { index: i, kind: "open" };
      tx.update(ref, { seats, memberUids: FieldValue.arrayRemove(uid), version: FieldValue.increment(1) });
      return;
    }
    if (room.status === "playing") {
      const m = room.match as MatchState;
      const s = m.seats[i];
      if (!s.eliminated) {
        // Leaving keeps your current table bank; you're out of this match.
        tx.set(db.collection("users").doc(uid), { gems: FieldValue.increment(s.bank), escrowRoom: null }, { merge: true });
        s.bank = 0;
        dropSeat(m, i);
      }
      commitMatch(tx, ref, m);
    }
  });
  return { ok: true };
});

export const startMatch = onCall(async (req) => {
  const uid = uidOf(req);
  await withRoom(req.data?.roomId, async (tx, ref, room) => {
    if (room.hostUid !== uid) throw new HttpsError("permission-denied", "Host only");
    if (room.status !== "lobby") throw new HttpsError("failed-precondition", "Already started");
    const lobby = room.seats as Seat[];
    const filled = lobby.filter((s) => s.kind !== "open");
    if (filled.length < 2) throw new HttpsError("failed-precondition", "Need at least 2 players");
    const humans = filled.filter((s) => s.uid);
    const userSnaps = await Promise.all(humans.map((s) => tx.get(db.collection("users").doc(s.uid))));
    const banks = new Map<string, number>();
    userSnaps.forEach((u, k) => {
      const gems = (u.data()?.gems as number) ?? 0;
      if (gems < room.ante) throw new HttpsError("failed-precondition", `${humans[k].displayName} lacks the ante`);
      if (u.data()?.escrowRoom) throw new HttpsError("failed-precondition", `${humans[k].displayName} is in another match`);
      banks.set(humans[k].uid, gems);
    });
    // Escrow: whole online balance moves to the table, returned on settle.
    for (const [u] of banks) tx.update(db.collection("users").doc(u), { gems: 0, escrowRoom: ref.id });
    // Open seats stay empty — never auto-filled with bots.
    const seats: SeatState[] = lobby.map((s, i) => ({
      index: i, kind: s.kind, uid: s.uid ?? null, displayName: s.displayName ?? null, connected: s.connected ?? false,
      bank: s.kind === "bot" ? BOT_START_BANK : s.uid ? banks.get(s.uid)! : 0, eliminated: false,
    }) as SeatState);
    const m = newMatch(seats, room.ante);
    tx.delete(db.collection("roomCodes").doc(room.code));
    commitMatch(tx, ref, m);
  });
  return { ok: true };
});

async function act(req: CallableRequest, fn: (m: MatchState, seat: number) => void) {
  const uid = uidOf(req);
  await withRoom(req.data?.roomId, async (tx, ref, room) => {
    if (room.status !== "playing") throw new HttpsError("failed-precondition", "Match not running");
    checkVersion(room, req.data?.expectedVersion);
    const m = room.match as MatchState;
    const seat = mySeat(room, uid);
    try { fn(m, seat); } catch (e) { asRuleError(e); }
    commitMatch(tx, ref, m);
  });
  return { ok: true };
}

/** Roll; optional `keep` = indexes held (ignored on first roll of a set). Server rolls. */
export const submitRoll = onCall((req) => act(req, (m, seat) => {
  const keep: number[] = Array.isArray(req.data?.keep) ? req.data.keep : [];
  roll(m, seat, [0, 1, 2].map((i) => keep.includes(i)), rng);
}));

/** Bank the current scoring hand (resolveTurn runs inside the engine). */
export const submitKeep = onCall((req) => act(req, (m, seat) => bank(m, seat)));

/** Host ends the match early: everyone keeps their table bank. */
export const endMatch = onCall(async (req) => {
  const uid = uidOf(req);
  await withRoom(req.data?.roomId, async (tx, ref, room) => {
    if (room.hostUid !== uid) throw new HttpsError("permission-denied", "Host only");
    if (room.status !== "playing") return;
    const m = room.match as MatchState;
    m.status = "finished";
    m.turn = null;
    const best = m.seats.filter((s) => s.kind !== "open" && !s.eliminated).sort((a, b) => b.bank - a.bank)[0];
    m.winnerSeat = best?.index ?? null;
    commitMatch(tx, ref, m);
  });
  return { ok: true };
});

/** Every minute: auto-play timed-out turns; abandon idle lobbies and free codes. */
export const sweepRooms = onSchedule("every 1 minutes", async () => {
  const now = Date.now();
  const late = await db.collection("rooms").where("status", "==", "playing").where("turnDeadline", "<", now).limit(50).get();
  for (const d of late.docs) {
    await withRoom(d.id, async (tx, ref, room) => {
      if (room.status !== "playing" || (room.turnDeadline ?? 0) >= now) return;
      const m = room.match as MatchState;
      autoPlayTimedOut(m, rng);
      commitMatch(tx, ref, m);
    }).catch(() => undefined);
  }
  const idle = await db.collection("rooms").where("status", "==", "lobby")
    .where("lastActivity", "<", Timestamp.fromMillis(now - LOBBY_IDLE_MS)).limit(100).get();
  for (const d of idle.docs) {
    const batch = db.batch();
    batch.update(d.ref, { status: "abandoned" });
    batch.delete(db.collection("roomCodes").doc(d.data().code));
    await batch.commit();
  }
});

/** "Delete my online data" (required before online Play review). */
export const deleteOnlineData = onCall(async (req) => {
  const uid = uidOf(req);
  const rooms = await db.collection("rooms").where("memberUids", "array-contains", uid).get();
  for (const doc of rooms.docs) {
    await withRoom(doc.id, async (tx, ref, room) => {
      const scrub = (s: Seat) => (s.uid === uid ? { index: s.index, kind: "open" } : s);
      const upd: Record<string, unknown> = { seats: (room.seats as Seat[]).map(scrub), memberUids: FieldValue.arrayRemove(uid) };
      if (room.status === "playing" && room.match) {
        const m = room.match as MatchState;
        const i = m.seats.findIndex((s) => s.uid === uid);
        if (i >= 0) {
          const s = m.seats[i];
          // Escrowed table bank is forfeited into the pot so the table stays whole for others.
          m.pot += s.bank; s.bank = 0;
          if (!s.eliminated) dropSeat(m, i);
          Object.assign(s, { uid: null, displayName: "Left player" });
        }
        if (room.hostUid === uid) {
          const next = m.seats.find((s) => s.uid && !s.eliminated);
          upd.hostUid = next?.uid ?? null;
        }
        tx.update(ref, upd);
        commitMatch(tx, ref, m);
        return;
      }
      if (room.status === "lobby" && room.hostUid === uid) {
        upd.status = "abandoned";
        tx.delete(db.collection("roomCodes").doc(room.code));
      }
      tx.update(ref, upd);
    });
  }
  await db.collection("users").doc(uid).delete();
  await getAuth().deleteUser(uid);
  return { ok: true, roomsScrubbed: rooms.size };
});

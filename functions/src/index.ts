/**
 * Marge invite-room multiplayer — Cloud Functions (callable, v2).
 * Server is authoritative for deck/dice, ante, pot and payouts.
 * See docs/multiplayer-invite-mvp.md for schema. Bodies marked TODO.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

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

export const leaveRoom = onCall(async (req) => {
  uidOf(req);
  // TODO: free seat in lobby; mark disconnected mid-match (turn timeout handles it).
  return { ok: true };
});

export const startMatch = onCall(async (req) => {
  uidOf(req);
  // TODO (host only): require >=2 non-open seats; open seats stay empty (no auto bot-fill);
  // debit ante from users/{uid}.gems for each human in one transaction; pot += antes;
  // write server-only rooms/{id}/private/state (dice RNG seed, turn order); status=playing.
  throw new HttpsError("unimplemented", "startMatch TODO");
});

export const submitRoll = onCall(async (req) => {
  uidOf(req);
  // TODO: verify turnSeat belongs to caller + expectedVersion; server rolls dice; bump version.
  throw new HttpsError("unimplemented", "submitRoll TODO");
});

export const submitKeep = onCall(async (req) => {
  uidOf(req);
  // TODO: validate keep indexes against server dice; advance turn; run bot seats server-side.
  throw new HttpsError("unimplemented", "submitKeep TODO");
});

/** Internal: evaluate hands, pay pot to users/{uid}.gems, status=finished. */
export async function resolveTurn(_roomId: string): Promise<void> {
  // TODO: port lib/engine/hand_evaluator.dart rules; pay out in a transaction.
}

/** Scheduled sweeper TODO: turn timeout (auto-pass after 60s), abandon lobbies idle 30 min, free codes. */

/** "Delete my online data" (required before online Play review). */
export const deleteOnlineData = onCall(async (req) => {
  const uid = uidOf(req);
  const rooms = await db.collection("rooms").where("memberUids", "array-contains", uid).get();
  const batch = db.batch();
  for (const doc of rooms.docs) {
    const seats = (doc.data().seats as Array<Record<string, unknown>>).map((s) =>
      s.uid === uid ? { index: s.index, kind: "open" } : s);
    batch.update(doc.ref, { seats, memberUids: FieldValue.arrayRemove(uid) });
  }
  batch.delete(db.collection("users").doc(uid));
  await batch.commit();
  await getAuth().deleteUser(uid);
  return { ok: true, roomsScrubbed: rooms.size };
});

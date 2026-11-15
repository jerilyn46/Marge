import assert from "node:assert/strict";
import { test } from "node:test";
import { autoPlayTimedOut, bank, dropSeat, MatchState, newMatch, roll, runBots, SeatState } from "../src/engine";
import {
  deadTokens, mergeTokens, MAX_TOKENS_PER_USER, sendTurnPush, TURN_CHANNEL_ID, turnPushMessage, turnPushRecipient,
  turnSnap, validToken,
} from "../src/push";

// Rng returning the given faces in order.
const seq = (vals: number[]) => { let i = 0; return () => (vals[i++ % vals.length] - 1) / 6 + 0.01; };
const human = (i: number, uid: string): SeatState =>
  ({ index: i, kind: i === 0 ? "host" : "human", uid, displayName: uid.toUpperCase(), bank: 100, eliminated: false });
const bot = (i: number): SeatState => ({ index: i, kind: "bot", displayName: `Bot ${i}`, bank: 100, eliminated: false });
const MISS = [2, 3, 6]; // never scores
const missTurn = (m: MatchState, seat: number) => { const r = seq(MISS); for (let k = 0; k < 3; k++) roll(m, seat, [false, false, false], r); };
const pick = (before: ReturnType<typeof turnSnap>, m: MatchState, actor: string | null) =>
  turnPushRecipient(before, m, actor, "room1", "ABC234");

test("match start: host acts and has the first turn → no push to the host", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  assert.equal(pick(null, m, "a"), null);
});

test("turn passes human → human: push the next player, not the actor", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  const before = turnSnap(m);
  missTurn(m, 0);
  assert.equal(m.turn!.seat, 1);
  assert.deepEqual(pick(before, m, "a"), { uid: "b", seat: 1, roomId: "room1", code: "ABC234" });
});

test("never pushes the player who just acted", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  const before = turnSnap(m);
  missTurn(m, 0);
  assert.equal(pick(before, m, "b"), null); // (e.g. b left / deleted and the turn landed on b — impossible, but guarded)
});

test("a scoring bank keeps the seat (set 2) → not a pass, no push", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  const before = turnSnap(m);
  roll(m, 0, undefined, seq([4, 5, 6])); // straight
  bank(m, 0);
  assert.equal(m.turn!.seat, 0);
  assert.equal(m.turn!.setNumber, 2);
  assert.equal(pick(before, m, "a"), null);
  assert.equal(pick(before, m, null), null);
});

test("bots never get a push; bots run and the turn comes back to the actor → no push", () => {
  const m = newMatch([human(0, "a"), bot(1), bot(2)], 10);
  const before = turnSnap(m);
  missTurn(m, 0);
  assert.equal(m.turn!.seat, 1);
  assert.equal(pick(before, m, "a"), null, "bot seat is never a recipient");
  runBots(m, seq([1, 2, 6, 3, 2, 6, 6, 2, 3]));
  if (m.status === "playing") {
    assert.equal(m.turn!.seat, 0);
    assert.equal(pick(before, m, "a"), null, "actor is never pushed");
  }
});

test("autoplay (sweepRooms): timed-out human busts → next human is pushed (actor null)", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  const before = turnSnap(m);
  autoPlayTimedOut(m, seq(MISS));
  assert.equal(m.turn!.seat, 1);
  assert.deepEqual(pick(before, m, null), { uid: "b", seat: 1, roomId: "room1", code: "ABC234" });
});

test("autoplay: turn laps all bots back to the timed-out human as a fresh set → push them", () => {
  const m = newMatch([human(0, "a"), bot(1)], 10);
  const before = turnSnap(m);
  autoPlayTimedOut(m, seq(MISS));
  runBots(m, seq(MISS)); // bot misses too
  assert.equal(m.status, "playing");
  assert.equal(m.turn!.seat, 0);
  assert.equal(m.turn!.setNumber, 1);
  assert.equal(pick(before, m, null)?.uid, "a");
});

test("autoplay of a bot seat → next human pushed", () => {
  const m = newMatch([human(0, "a"), bot(1), human(2, "c")], 10);
  missTurn(m, 0);
  const before = turnSnap(m); // bot 1's turn (as if runBots had not run)
  autoPlayTimedOut(m, seq(MISS));
  assert.equal(m.turn!.seat, 2);
  assert.equal(pick(before, m, null)?.uid, "c");
});

test("leave passes the turn: the leaver is not pushed, the next player is", () => {
  const m = newMatch([human(0, "a"), human(1, "b"), human(2, "c")], 10);
  const before = turnSnap(m);
  dropSeat(m, 0);
  assert.equal(m.turn!.seat, 1);
  assert.equal(pick(before, m, "a")?.uid, "b");
});

test("finished match / no turn / eliminated / uid-less seats → no push", () => {
  const m = newMatch([human(0, "a"), human(1, "b")], 10);
  const before = turnSnap(m);
  dropSeat(m, 1); // one left → finished
  assert.equal(m.status, "finished");
  assert.equal(pick(before, m, "b"), null);

  const m2 = newMatch([human(0, "a"), human(1, "b")], 10);
  const b2 = turnSnap(m2);
  missTurn(m2, 0);
  m2.seats[1].uid = undefined; // "Left player" scrub
  assert.equal(pick(b2, m2, "a"), null);
  m2.seats[1].uid = "b"; m2.seats[1].eliminated = true;
  assert.equal(pick(b2, m2, "a"), null);
});

test("push message: title names the room, Android channel, data for the tap, short TTL, collapsed per room", () => {
  const msg = turnPushMessage({ uid: "b", seat: 1, roomId: "r9", code: "EE7LWC" }, ["t1"]);
  assert.equal(msg.notification.title, "Your turn in Marge (room EE7LWC)");
  assert.deepEqual(msg.data, { type: "turn", roomId: "r9", code: "EE7LWC" });
  assert.equal(msg.android.notification.channelId, TURN_CHANNEL_ID);
  assert.equal(msg.android.notification.tag, "turn-r9");
  assert.ok(msg.android.ttl <= 120_000);
  assert.equal(turnPushMessage({ uid: "b", seat: 1, roomId: "r9", code: "" }, ["t"]).notification.title, "Your turn in Marge");
});

test("token store: newest first, dedupe, replaces old on refresh, capped", () => {
  assert.deepEqual(mergeTokens(undefined, "t1"), ["t1"]);
  assert.deepEqual(mergeTokens(["t1", "t2"], "t2"), ["t2", "t1"]);
  assert.deepEqual(mergeTokens(["old", "t2"], "new", "old"), ["new", "t2"]);
  const many = Array.from({ length: 10 }, (_, i) => `t${i}`);
  assert.equal(mergeTokens(many, "x").length, MAX_TOKENS_PER_USER);
  assert.ok(validToken("x".repeat(150)));
  assert.ok(!validToken("short"));
  assert.ok(!validToken(42));
  assert.ok(!validToken("has space ".repeat(5)));
});

test("dead tokens are pruned; transient errors are kept", () => {
  const dead = deadTokens(["a", "b", "c", "d"], [
    { success: true },
    { success: false, error: { code: "messaging/registration-token-not-registered" } },
    { success: false, error: { code: "messaging/internal-error" } },
    { success: false, error: { code: "messaging/invalid-registration-token" } },
  ]);
  assert.deepEqual(dead, ["b", "d"]);
  // Live FCM (marge-online, 2026-11-15) answers a malformed token with invalid-argument + this text.
  assert.deepEqual(deadTokens(["x", "y"], [
    { success: false, error: { code: "messaging/invalid-argument", message: "The registration token is not a valid FCM registration token" } },
    { success: false, error: { code: "messaging/invalid-argument", message: "Invalid JSON payload received." } },
  ]), ["x"], "payload errors never prune tokens");
});

test("sendTurnPush: sends to the recipient's tokens, prunes, never throws", async () => {
  const removed: string[][] = [];
  const sentTo: string[][] = [];
  const deps = {
    getTokens: async (uid: string) => (uid === "b" ? ["good", "gone"] : []),
    send: async (msg: { tokens: string[] }) => {
      sentTo.push(msg.tokens);
      return { responses: [{ success: true }, { success: false, error: { code: "messaging/registration-token-not-registered" } }] };
    },
    removeTokens: async (_uid: string, d: string[]) => { removed.push(d); },
  };
  const p = { uid: "b", seat: 1, roomId: "r", code: "C" };
  assert.deepEqual(await sendTurnPush(p, deps), { sent: 1, pruned: 1 });
  assert.deepEqual(sentTo, [["good", "gone"]]);
  assert.deepEqual(removed, [["gone"]]);
  // No tokens → no send.
  assert.deepEqual(await sendTurnPush({ ...p, uid: "nobody" }, deps), { sent: 0, pruned: 0 });
  assert.equal(sentTo.length, 1);
  // null recipient → nothing.
  assert.deepEqual(await sendTurnPush(null, deps), { sent: 0, pruned: 0 });
  // FCM failure is swallowed (a push must never fail a move).
  const boom = { ...deps, send: async () => { throw new Error("FCM down"); } };
  assert.deepEqual(await sendTurnPush(p, boom), { sent: 0, pruned: 0 });
});

test("someone else leaves while it's my fresh turn → turn untouched, no push (played=false)", () => {
  const m = newMatch([human(0, "a"), human(1, "b"), human(2, "c")], 10);
  const before = turnSnap(m); // a, set 1, roll 0
  dropSeat(m, 2);
  assert.equal(m.turn!.seat, 0);
  assert.equal(turnPushRecipient(before, m, "c", "room1", "ABC234", false), null);
});

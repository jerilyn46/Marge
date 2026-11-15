import assert from "node:assert/strict";
import { test } from "node:test";
import { dropSeat, MatchState, newMatch, roll, SeatState, settlePot } from "../src/engine";
import { ABANDONED_RETENTION_MS, FINISHED_RETENTION_MS, LEFT_NAME, scrubRoom, settleFinishedPot, sweepAction } from "../src/rooms";

const human = (i: number, uid: string, name: string, bank: number): SeatState =>
  ({ index: i, kind: i === 0 ? "host" : "human", uid, displayName: name, bank, eliminated: false });
const bot = (i: number, bank = 100): SeatState => ({ index: i, kind: "bot", displayName: `Bot ${i}`, bank, eliminated: false });
const total = (m: MatchState) => m.seats.reduce((a, s) => a + s.bank, 0) + m.pot;
const finished = (seats: SeatState[], pot: number): MatchState =>
  ({ seats, ante: 10, pot, round: 1, turn: null, status: "finished", winnerSeat: 0, lastPayout: null });

test("settlePot: proportional to bank, conserves, deterministic largest remainder", () => {
  const m = finished([human(0, "a", "A", 30), human(1, "b", "B", 20), bot(2, 50)], 7);
  const before = total(m);
  const split = settlePot(m);
  assert.equal(m.pot, 0);
  assert.equal(total(m), before);
  // 7*30/100=2.1, 7*20/100=1.4, 7*50/100=3.5 → floors 2,1,3 (=6); +1 to largest remainder (seat 2)
  assert.deepEqual(split, [[0, 2], [1, 1], [2, 4]]);
  assert.deepEqual(m.seats.map((s) => s.bank), [32, 21, 54]);
});

test("settlePot: ties go to lower seat; eliminated/open seats get nothing", () => {
  const out = { ...human(1, "b", "B", 0), eliminated: true };
  const open = { index: 3, kind: "open", bank: 0, eliminated: false } as SeatState;
  const m = finished([human(0, "a", "A", 10), out, human(2, "c", "C", 10), open], 5);
  settlePot(m);
  assert.deepEqual(m.seats.map((s) => s.bank), [13, 0, 12, 0]);
});

test("settlePot: lone survivor takes all; no-op when not finished or empty", () => {
  const m = finished([human(0, "a", "A", 40), { ...human(1, "b", "B", 0), eliminated: true }], 25);
  settlePot(m);
  assert.equal(m.seats[0].bank, 65);
  const p = newMatch([human(0, "a", "A", 50), human(1, "b", "B", 50)], 10);
  assert.deepEqual(settlePot(p), []);
  assert.equal(p.pot, 20);
});

test("settlePot: nobody still in → equal split over seats that still have a uid", () => {
  const gone = (s: SeatState) => ({ ...s, eliminated: true });
  const m = finished([gone(human(0, "a", "A", 0)), gone({ ...human(1, "", LEFT_NAME, 0), uid: undefined }), gone(human(2, "c", "C", 0))], 9);
  settlePot(m);
  assert.deepEqual(m.seats.map((s) => s.bank), [5, 0, 4]);
  assert.equal(m.pot, 0);
});

const lobbyRoom = () => ({
  status: "lobby", hostUid: "a", code: "ABCDEF", memberUids: ["a", "b"],
  seats: [{ index: 0, kind: "host", uid: "a", displayName: "Alice" }, { index: 1, kind: "human", uid: "b", displayName: "Bob" }],
});

test("scrubRoom: lobby guest → seat open, member removed, room kept", () => {
  const p = scrubRoom(lobbyRoom(), "b");
  assert.equal(p.deleteRoom, false);
  assert.equal(p.freeCode, false);
  assert.deepEqual(p.fields.memberUids, ["a"]);
  assert.ok(!JSON.stringify(p.fields).includes("Bob"));
});

test("scrubRoom: lobby host with guest → abandoned, code freed, host passes", () => {
  const p = scrubRoom(lobbyRoom(), "a");
  assert.equal(p.fields.status, "abandoned");
  assert.equal(p.fields.hostUid, "b");
  assert.equal(p.freeCode, true);
  assert.equal(p.deleteRoom, false);
});

test("scrubRoom: last member → delete room", () => {
  const r = { ...lobbyRoom(), memberUids: ["a"], seats: [lobbyRoom().seats[0]] };
  const p = scrubRoom(r, "a");
  assert.equal(p.deleteRoom, true);
  assert.equal(p.freeCode, true);
});

test("scrubRoom: playing → bank forfeited to pot, seat dropped, room playable, conserved", () => {
  const m = newMatch([human(0, "a", "Alice", 50), human(1, "b", "Bob", 50), bot(2)], 10);
  m.lastPayout = { message: "Bob hits a straight! Collects 10 gems.", kind: "straight", amount: 10, seat: 1, dice: [1, 2, 3] };
  const before = total(m);
  const room = { status: "playing", hostUid: "a", code: "ABCDEF", memberUids: ["a", "b"], seats: lobbyRoom().seats, match: m };
  const p = scrubRoom(room, "b");
  const pm = p.match!;
  assert.equal(p.wasPlaying, true);
  assert.equal(p.deleteRoom, false);
  assert.equal(pm.status, "playing");
  assert.equal(pm.seats[1].eliminated, true);
  assert.notEqual(pm.turn!.seat, 1);
  assert.equal(total(pm), before);
  const blob = JSON.stringify({ ...p.fields, match: pm });
  assert.ok(!blob.includes("\"b\"") && !blob.includes("Bob"), blob);
  assert.equal(pm.seats[1].displayName, LEFT_NAME);
  assert.equal(room.match.seats[1].uid, "b", "input not mutated");
});

test("scrubRoom: finished room is anonymized too; host passes on", () => {
  const m = finished([human(0, "a", "Alice", 60), human(1, "b", "Bob", 40)], 0);
  m.lastPayout = { message: "Alice hits three 4s! Bob out of gems. — Alice wins the pot (20 gems).", kind: "threeOfAKind", amount: 4, seat: 0, dice: [4, 4, 4] };
  const room = { status: "finished", hostUid: "a", code: "ABCDEF", memberUids: ["a", "b"], seats: lobbyRoom().seats, match: m };
  const p = scrubRoom(room, "a");
  const blob = JSON.stringify({ ...p.fields, match: p.match });
  assert.ok(!blob.includes("\"a\"") && !blob.includes("Alice"), blob);
  assert.equal(p.fields.hostUid, "b");
  assert.equal(p.match!.seats[0].bank, 60, "finished banks untouched");
  assert.equal(p.wasPlaying, false);
  assert.equal(p.deleteRoom, false);
  assert.equal(scrubRoom({ ...room, memberUids: ["a"] }, "a").deleteRoom, true);
});

test("sweepAction: autoplay / abandon / retention deletes", () => {
  const now = 10 * FINISHED_RETENTION_MS, idle = 30 * 60_000;
  assert.equal(sweepAction({ status: "playing", turnDeadline: now - 1 }, now, idle), "autoplay");
  assert.equal(sweepAction({ status: "playing", turnDeadline: now + 1 }, now, idle), null);
  assert.equal(sweepAction({ status: "lobby", lastActivity: now - idle - 1 }, now, idle), "abandon");
  assert.equal(sweepAction({ status: "lobby", lastActivity: now - 1 }, now, idle), null);
  assert.equal(sweepAction({ status: "finished", lastActivity: { toMillis: () => now - FINISHED_RETENTION_MS - 1 } }, now, idle), "delete");
  assert.equal(sweepAction({ status: "finished", lastActivity: now - 60_000 }, now, idle), null);
  assert.equal(sweepAction({ status: "abandoned", lastActivity: now - ABANDONED_RETENTION_MS - 1 }, now, idle), "delete");
  assert.equal(sweepAction({ status: "abandoned", lastActivity: now - 1 }, now, idle), null);
});

test("leave mid-match: fresh lastPayout (no stale whiff kind/amount), pot goes to the stayer (Y7PE55)", () => {
  const m = newMatch([human(0, "a", "Jerilyn", 100), human(1, "b", "Box Tester", 100)], 10);
  // Seat 0 whiffs (turn → seat 1), seat 1 whiffs (turn → seat 0): lastPayout = Box Tester whiffs, amount 2.
  let i = 0; const f = [2, 3, 6]; const r = () => (f[i++ % 3] - 1) / 6 + 0.01;
  for (const seat of [0, 1]) for (let k = 0; k < 3; k++) roll(m, seat, [false, false, false], r);
  assert.match(m.lastPayout!.message, /Box Tester whiffs/);
  assert.equal(m.lastPayout!.amount, 2);
  const pot = m.pot;
  const stayer = m.seats[1].bank;
  // leaveRoom: leaver keeps their bank (paid out), seat dropped → match finishes.
  m.seats[0].bank = 0;
  dropSeat(m, 0);
  assert.equal(m.status, "finished");
  settleFinishedPot(m);
  assert.equal(m.lastPayout!.message, `Jerilyn left the table. Pot of ${pot} goes to Box Tester.`);
  assert.equal(m.lastPayout!.kind, "none");
  assert.equal(m.lastPayout!.amount, 0);
  assert.equal(m.lastPayout!.seat, 0);
  assert.deepEqual(m.lastPayout!.dice, []);
  assert.ok(!m.lastPayout!.message.includes("whiffs"));
  assert.equal(m.pot, 0);
  assert.equal(m.seats[1].bank, stayer + pot, "stayer gets the whole pot");
});

test("leave with 3+ players: '<Name> left the table.' and play continues", () => {
  const m = newMatch([human(0, "a", "A", 100), human(1, "b", "B", 100), human(2, "c", "C", 100)], 10);
  m.lastPayout = { message: "B whiffs — 2 gems to the pot.", kind: "none", amount: 2, seat: 1, dice: [2, 3, 6] };
  dropSeat(m, 2);
  assert.equal(m.status, "playing");
  assert.deepEqual(m.lastPayout, { message: "C left the table.", kind: "none", amount: 0, seat: 2, dice: [] });
});

test("finished pot split over several seats keeps the proportional line", () => {
  const m = finished([human(0, "a", "A", 30), human(1, "b", "B", 20)], 5);
  m.lastPayout = { message: "A ended the match.", kind: "none", amount: 0, seat: 0, dice: [] };
  settleFinishedPot(m);
  assert.equal(m.lastPayout!.message, "A ended the match. Pot of 5 returned by table bank: A +3, B +2.");
});

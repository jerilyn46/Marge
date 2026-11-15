import assert from "node:assert/strict";
import { test } from "node:test";
import { autoPlayTimedOut, botAct, newMatch, safeHold, SeatState, MISSED_ONES_PENALTY, BUST_PENALTY } from "../src/engine";

// Rng returning the given faces in order.
const seq = (vals: number[]) => { let i = 0; return () => (vals[i++ % vals.length] - 1) / 6 + 0.01; };
const seats = (k1: SeatState["kind"] = "human"): SeatState[] => [
  { index: 0, kind: "host", uid: "a", displayName: "A", bank: 100, eliminated: false },
  { index: 1, kind: k1, uid: k1 === "bot" ? undefined : "b", displayName: "B", bank: 100, eliminated: false },
];

test("safeHold never holds a pair of 1s", () => {
  const h = safeHold([1, 1, 6]);
  assert.ok(!(h[0] && h[1]), "must not hold 1,1");
});

test("safeHold prefers an open-ended straight draw (2 outs) over a pair (1 out)", () => {
  assert.deepEqual(safeHold([3, 4, 4]), [true, true, false]); // 3-4 needs 2 or 5
  assert.deepEqual(safeHold([6, 6, 1]), [true, true, false]); // 6-6 (1 out) beats 6-1/1-6 (0 outs)
});

test("records startBanks for the result screen", () => {
  const m = newMatch(seats(), 10);
  assert.deepEqual(m.startBanks, [100, 100]);
});

test("timed-out human banks a scoring roll at once", () => {
  const m = newMatch(seats(), 10); // pot 20, A 90, B 90
  autoPlayTimedOut(m, seq([4, 5, 6])); // straight on roll 1
  assert.equal(m.seats[0].bank, 95);
  assert.equal(m.seats[1].bank, 85);
  // one set only: A keeps the seat with a fresh set, not auto-played further
  assert.equal(m.turn!.seat, 0);
  assert.equal(m.turn!.setNumber, 2);
  assert.equal(m.turn!.rollNumber, 0);
});

test("timed-out human holding 1,1 does not chase triple ones: a miss costs 2, not 10", () => {
  const m = newMatch(seats(), 10);
  // roll1 1,1,6 (none) -> safe hold keeps 1-6? (0 outs) / 1,1 is excluded; dice keep coming up misses
  autoPlayTimedOut(m, seq([1, 1, 6, 1, 1, 6, 1, 1, 6]));
  assert.equal(m.lastPayout!.missedTripleOnes, false);
  assert.equal(m.lastPayout!.amount, BUST_PENALTY);
  assert.equal(m.pot, 20 + BUST_PENALTY);
  assert.equal(m.turn!.seat, 1);
});

test("bots keep their old policy (may hold 1,1 and pay the missed-ones penalty)", () => {
  const m = newMatch(seats("bot"), 10);
  // Seat 0 human busts, then bot seat 1 is run by commit; here drive botAct directly.
  m.turn!.seat = 1;
  const r = seq([1, 1, 6, 5, 4]);
  botAct(m, r); // 1,1,6
  botAct(m, r); // holds 1,1 -> 1,1,5
  botAct(m, r); // holds 1,1 -> 1,1,4 miss
  assert.equal(m.lastPayout!.missedTripleOnes, true);
  assert.equal(m.lastPayout!.amount, MISSED_ONES_PENALTY);
});

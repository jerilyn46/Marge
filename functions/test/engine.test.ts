import assert from "node:assert/strict";
import { test } from "node:test";
import { bank, evaluate, newMatch, roll, runBots, SeatState } from "../src/engine";

const seq = (vals: number[]) => { let i = 0; return () => (vals[i++ % vals.length] - 1) / 6 + 0.01; };
const seats = (): SeatState[] => [
  { index: 0, kind: "host", uid: "a", displayName: "A", bank: 100, eliminated: false },
  { index: 1, kind: "human", uid: "b", displayName: "B", bank: 100, eliminated: false },
];

test("evaluate parity with hand_evaluator.dart", () => {
  assert.equal(evaluate([1, 1, 1], 1).kind, "tripleOnesPotWin");
  assert.deepEqual([evaluate([1, 1, 1], 2).kind, evaluate([1, 1, 1], 2).perOpponent], ["tripleOnesPay", 10]);
  assert.equal(evaluate([4, 4, 4], 1).perOpponent, 8);
  assert.equal(evaluate([4, 4, 4], 1).bankedOnly, true);
  assert.equal(evaluate([4, 4, 4], 3).perOpponent, 4);
  assert.equal(evaluate([3, 1, 2], 2).kind, "straight");
  assert.equal(evaluate([6, 4, 5], 1).perOpponent, 5);
  assert.equal(evaluate([1, 3, 5], 1).kind, "none");
  assert.equal(evaluate([2, 2, 5], 1).kind, "none");
});

test("ante, straight banks and keeps seat", () => {
  const m = newMatch(seats(), 10);
  assert.equal(m.pot, 20);
  roll(m, 0, undefined, seq([1, 2, 3]));
  bank(m, 0);
  assert.equal(m.seats[0].bank, 95);
  assert.equal(m.seats[1].bank, 85);
  assert.equal(m.turn!.seat, 0);
  assert.equal(m.turn!.setNumber, 2);
});

test("bust after 3 rolls → 2 to pot, seat passes", () => {
  const m = newMatch(seats(), 10);
  const r = seq([1, 3, 5, 6, 2, 4]); // 1,3,5 then reroll held? hold none
  roll(m, 0, undefined, r);
  assert.throws(() => bank(m, 0));
  roll(m, 0, [true, true, false], seq([6]));   // 1,3,6
  roll(m, 0, [true, true, false], seq([5]));   // 1,3,5 none
  assert.equal(m.pot, 22);
  assert.equal(m.turn!.seat, 1);
});

test("missed triple ones → 10 to pot", () => {
  const m = newMatch(seats(), 10);
  roll(m, 0, undefined, seq([1, 1, 4]));
  roll(m, 0, [true, true, false], seq([5]));
  roll(m, 0, [true, true, false], seq([6]));
  assert.equal(m.pot, 30);
  assert.equal(m.lastPayout!.missedTripleOnes, true);
});

test("first-roll triple ones wins pot and ends match", () => {
  const m = newMatch(seats(), 10);
  roll(m, 0, undefined, seq([1, 1, 1]));
  assert.equal(m.status, "finished");
  assert.equal(m.seats[0].bank, 90 + 10 + 20);
  assert.equal(m.winnerSeat, 0);
});

test("wrong seat refused; bots run until human", () => {
  const s = seats();
  s[1] = { index: 1, kind: "bot", displayName: "Bot", bank: 100, eliminated: false };
  const m = newMatch(s, 10);
  assert.throws(() => roll(m, 1, undefined, Math.random));
  roll(m, 0, undefined, seq([1, 3, 5]));
  roll(m, 0, [false, false, false], seq([1, 3, 5]));
  roll(m, 0, [false, false, false], seq([1, 3, 5]));
  runBots(m, Math.random);
  assert.ok(m.status === "finished" || m.turn!.seat === 0);
});

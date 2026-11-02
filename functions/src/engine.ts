/**
 * Server-side Marge rules. Port of lib/engine/hand_evaluator.dart +
 * the payout core of lib/engine/match_controller.dart. Pure functions over
 * a plain MatchState so they can be unit-tested without Firebase.
 *
 * Known simplifications vs local engine (see docs, "Parity risks"):
 *  - No House stake top-up.
 *  - No human shortfall choice: anyone short pays what they have; at 0 they are out.
 *  - No handoff confirm step: turn passes immediately; lastPayout is shown.
 */

export type ScoreKind = "tripleOnesPotWin" | "tripleOnesPay" | "threeOfAKind" | "straight" | "none";

export interface ScoreResult {
  kind: ScoreKind;
  face?: number;
  perOpponent: number;
  takesPot: boolean;
  bankedOnly: boolean; // first-roll trips 2–6
}

export const BUST_PENALTY = 2;
export const MISSED_ONES_PENALTY = 10;
export const FIRST_ROLL_ONES_EACH = 10;
export const BOT_START_BANK = 100;

const STRAIGHTS = [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6]];

export function evaluate(values: number[], rollNumber: number): ScoreResult {
  const counts = new Map<number, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  for (const [face, n] of counts) {
    if (n === 3) {
      if (face === 1) {
        return rollNumber === 1
          ? { kind: "tripleOnesPotWin", face: 1, perOpponent: 0, takesPot: true, bankedOnly: false }
          : { kind: "tripleOnesPay", face: 1, perOpponent: 10, takesPot: false, bankedOnly: false };
      }
      const first = rollNumber === 1;
      return { kind: "threeOfAKind", face, perOpponent: first ? face * 2 : face, takesPot: false, bankedOnly: first };
    }
  }
  const set = new Set(values);
  if (set.size === 3 && STRAIGHTS.some((s) => s.every((x) => set.has(x)))) {
    return { kind: "straight", perOpponent: 5, takesPot: false, bankedOnly: false };
  }
  return { kind: "none", perOpponent: 0, takesPot: false, bankedOnly: false };
}

export interface SeatState {
  index: number;
  kind: "host" | "human" | "bot" | "open";
  uid?: string;
  displayName?: string;
  connected?: boolean;
  bank: number;
  eliminated: boolean;
}

export interface TurnState {
  seat: number;
  rollNumber: number; // 0..3
  setNumber: number;
  dice: number[];
  kept: boolean[];
  carried: (number | null)[] | null;
  score: ScoreResult | null;
}

export interface Payout {
  message: string;
  kind: ScoreKind;
  amount: number;
  seat: number;
  dice: number[];
  missedTripleOnes?: boolean;
}

export interface MatchState {
  seats: SeatState[];
  ante: number;
  pot: number;
  round: number;
  turn: TurnState | null;
  status: "playing" | "finished";
  winnerSeat: number | null;
  lastPayout: Payout | null;
}

export type Rng = () => number; // [0,1)

const plays = (s: SeatState) => s.kind !== "open" && !s.eliminated;
const playable = (m: MatchState) => m.seats.filter(plays).length;
const name = (m: MatchState, i: number) => m.seats[i].displayName ?? `Seat ${i + 1}`;

function take(m: MatchState, i: number, amount: number): number {
  const s = m.seats[i];
  if (!plays(s) || amount <= 0) return 0;
  const paid = Math.min(s.bank, amount);
  s.bank -= paid;
  return paid;
}

function kickZeroed(m: MatchState, idx: number[]): number[] {
  const out: number[] = [];
  for (const i of idx) {
    const s = m.seats[i];
    if (plays(s) && s.bank <= 0) { s.eliminated = true; out.push(i); }
  }
  return out;
}

function firstActive(m: MatchState, from: number): number {
  for (let step = 0; step < m.seats.length; step++) {
    const i = (from + step) % m.seats.length;
    if (plays(m.seats[i])) return i;
  }
  return from;
}

function startTurn(m: MatchState, seat: number, setNumber = 1) {
  m.turn = { seat, rollNumber: 0, setNumber, dice: [1, 1, 1], kept: [false, false, false], carried: null, score: null };
}

function endMatch(m: MatchState, winner?: number) {
  m.status = "finished";
  m.turn = null;
  if (winner !== undefined) { m.winnerSeat = winner; return; }
  const sorted = m.seats.map((s, i) => ({ s, i })).filter((x) => plays(x.s)).sort((a, b) => b.s.bank - a.s.bank);
  m.winnerSeat = sorted.length ? sorted[0].i : null;
}

function sweepPotTo(m: MatchState, winner: number, why: string) {
  const pot = m.pot;
  m.seats[winner].bank += pot;
  m.pot = 0;
  m.lastPayout = { message: `${why} — ${name(m, winner)} wins the pot (${pot} gems).`, kind: "tripleOnesPotWin",
    amount: pot, seat: winner, dice: m.turn?.dice ?? [] };
  endMatch(m, winner);
}

/** Collect ante from every seated player; first active seat starts. */
export function beginRound(m: MatchState) {
  m.round += 1;
  m.lastPayout = null;
  const payers: number[] = [];
  m.seats.forEach((s, i) => { if (plays(s)) { m.pot += take(m, i, m.ante); payers.push(i); } });
  const kicked = kickZeroed(m, payers);
  if (kicked.length && playable(m) === 1) {
    sweepPotTo(m, m.seats.findIndex(plays), `${kicked.map((i) => name(m, i)).join(", ")} paid the ante and is out`);
    return;
  }
  if (playable(m) <= 1) { endMatch(m); return; }
  startTurn(m, firstActive(m, 0));
}

export function newMatch(seats: SeatState[], ante: number): MatchState {
  const m: MatchState = { seats, ante, pot: 0, round: 0, turn: null, status: "playing", winnerSeat: null, lastPayout: null };
  beginRound(m);
  return m;
}

export class RuleError extends Error {}

/** Apply hold flags then roll non-held dice (all on first roll of a set). */
export function roll(m: MatchState, seat: number, kept: boolean[] | undefined, rng: Rng) {
  const t = m.turn;
  if (m.status !== "playing" || !t) throw new RuleError("No turn in progress");
  if (t.seat !== seat) throw new RuleError("Not your turn");
  if (t.rollNumber >= 3) throw new RuleError("No rolls left");
  const first = t.rollNumber === 0;
  const hold = first ? [false, false, false] : (kept ?? t.kept).map(Boolean).slice(0, 3);
  const nextRoll = t.rollNumber + 1;
  const carried = nextRoll === 3 ? t.dice.map((v, i) => (hold[i] ? v : null)) : null;
  const die = () => Math.floor(rng() * 6) + 1;
  t.dice = t.dice.map((v, i) => (hold[i] ? v : die()));
  t.kept = hold;
  t.rollNumber = nextRoll;
  t.carried = carried;
  t.score = evaluate(t.dice, nextRoll);
  m.lastPayout = null;
  if (t.score.kind === "tripleOnesPotWin") return resolve(m);
  if (t.score.kind === "none" && nextRoll >= 3) return resolve(m);
}

/** Bank a scoring hand. Refuses to bank a miss while rolls remain. */
export function bank(m: MatchState, seat: number) {
  const t = m.turn;
  if (m.status !== "playing" || !t) throw new RuleError("No turn in progress");
  if (t.seat !== seat) throw new RuleError("Not your turn");
  if (!t.score || (t.score.kind === "none" && t.rollNumber < 3)) throw new RuleError("Cannot bank a miss — keep rolling");
  resolve(m);
}

function wentForTripleOnes(t: TurnState): boolean {
  if (t.rollNumber !== 3 || t.dice.every((v) => v === 1)) return false;
  const held = (t.carried ?? []).filter((v): v is number => v !== null);
  return held.length === 2 && held.every((v) => v === 1);
}

function advance(m: MatchState) {
  if (playable(m) <= 1) { endMatch(m); return; }
  startTurn(m, firstActive(m, m.turn!.seat + 1));
}

function resolve(m: MatchState) {
  const t = m.turn!;
  const score = t.score!;
  const roller = t.seat;
  const dice = [...t.dice];
  const others = m.seats.map((_, i) => i).filter((i) => i !== roller && plays(m.seats[i]));

  if (score.kind === "tripleOnesPotWin") {
    let collected = 0;
    for (const i of others) { const p = take(m, i, FIRST_ROLL_ONES_EACH); collected += p; m.seats[i].bank === 0 && (m.seats[i].eliminated = true); }
    m.seats[roller].bank += collected;
    const pot = m.pot;
    m.seats[roller].bank += pot;
    m.pot = 0;
    m.lastPayout = { message: `${name(m, roller)} rolled three 1s on the first roll! Everyone pays ${FIRST_ROLL_ONES_EACH} and ${name(m, roller)} wins the pot.`,
      kind: score.kind, amount: pot + collected, seat: roller, dice };
    endMatch(m, roller);
    return;
  }

  if (score.kind !== "none") {
    let total = 0;
    for (const i of others) total += take(m, i, score.perOpponent);
    m.seats[roller].bank += total;
    const kicked = kickZeroed(m, others);
    const label = score.kind === "straight" ? "a straight" : score.kind === "tripleOnesPay" ? "triple ones" : `three ${score.face}s`;
    m.lastPayout = { message: `${name(m, roller)} hits ${label}! Collects ${total} gems.` +
      (kicked.length ? ` ${kicked.map((i) => name(m, i)).join(", ")} out of gems.` : ""), kind: score.kind, amount: total, seat: roller, dice };
    if (kicked.length && playable(m) <= 1) { const msg = m.lastPayout.message; sweepPotTo(m, roller, msg); return; }
    if (playable(m) <= 1) { endMatch(m); return; }
    const payout = m.lastPayout;
    startTurn(m, roller, t.setNumber + 1); // win keeps the seat, fresh 3 rolls
    m.lastPayout = payout;
    return;
  }

  // Miss after 3 rolls.
  const missedOnes = wentForTripleOnes(t);
  const due = missedOnes ? MISSED_ONES_PENALTY : BUST_PENALTY;
  const paid = take(m, roller, due);
  m.pot += paid;
  m.lastPayout = { message: missedOnes ? `${name(m, roller)} missed triple ones — ${paid} gems to the pot.` : `${name(m, roller)} whiffs — ${paid} gems to the pot.`,
    kind: "none", amount: paid, seat: roller, dice, missedTripleOnes: missedOnes };
  const kicked = kickZeroed(m, [roller]);
  if (kicked.length && playable(m) === 1) { sweepPotTo(m, m.seats.findIndex(plays), `${name(m, roller)} is out of gems`); return; }
  const payout = m.lastPayout;
  advance(m);
  m.lastPayout = payout;
}

/** Simple server bot: hold pairs / 1s, bank any scoring hand. */
export function botAct(m: MatchState, rng: Rng) {
  const t = m.turn!;
  if (t.rollNumber > 0 && t.score && t.score.kind !== "none") return bank(m, t.seat);
  let kept = [false, false, false];
  if (t.rollNumber > 0) {
    const counts = new Map<number, number>();
    t.dice.forEach((v) => counts.set(v, (counts.get(v) ?? 0) + 1));
    const pair = [...counts].find(([, n]) => n === 2)?.[0];
    kept = t.dice.map((v) => (pair !== undefined ? v === pair : false));
  }
  roll(m, t.seat, kept, rng);
}

/** Run bot seats until a human is up or the match ends. */
export function runBots(m: MatchState, rng: Rng, maxSteps = 200) {
  for (let i = 0; i < maxSteps && m.status === "playing" && m.turn && m.seats[m.turn.seat].kind === "bot"; i++) botAct(m, rng);
}

/** Turn timeout: auto-play the current human seat like a bot (one full set). */
export function autoPlayTimedOut(m: MatchState, rng: Rng) {
  const seat = m.turn?.seat;
  for (let i = 0; i < 6 && m.status === "playing" && m.turn?.seat === seat; i++) botAct(m, rng);
}

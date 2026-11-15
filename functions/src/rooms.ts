/**
 * Pure room-document helpers (no Firebase), unit-tested in test/rooms.test.ts.
 */
import { dropSeat, MatchState, settlePot } from "./engine";

export const LEFT_NAME = "Left player";
export const FINISHED_RETENTION_MS = 24 * 60 * 60_000; // results stay readable a day
export const ABANDONED_RETENTION_MS = 60 * 60_000;

type Seat = Record<string, any>;
export type Room = Record<string, any>;

export interface ScrubPlan {
  /** No human member left: delete the room doc (and its code if still held). */
  deleteRoom: boolean;
  /** Free roomCodes/{code} (lobby only; started rooms already freed it). */
  freeCode: boolean;
  /** Top-level fields to write (seats, memberUids, hostUid, status). */
  fields: Record<string, unknown>;
  /** Mutated match, if the room has one. Run it through commitMatch when wasPlaying. */
  match: MatchState | null;
  wasPlaying: boolean;
}

/**
 * Remove every trace of `uid` from a room, whatever its status:
 * lobby seat → open; match seat → uid null + "Left player" (finished match:
 * uid null, name and result text kept — never "Left player"); (and, if the match
 * is running, its table bank forfeited to the pot and the seat dropped so the
 * others keep playing); the name is also scrubbed from lastPayout; hostUid
 * passes to the next member. If no member is left, the room is deleted.
 */
export function scrubRoom(room: Room, uid: string): ScrubPlan {
  const seats = (room.seats as Seat[] | undefined) ?? [];
  const mine = seats.find((s) => s.uid === uid);
  const names = new Set<string>();
  if (mine?.displayName) names.add(mine.displayName);
  const memberUids = ((room.memberUids as string[] | undefined) ?? []).filter((u) => u !== uid);
  const fields: Record<string, unknown> = {
    seats: seats.map((s) => (s.uid === uid ? { index: s.index, kind: "open" } : s)),
    memberUids,
  };
  const wasPlaying = room.status === "playing" && !!room.match;
  let match: MatchState | null = room.match ? (JSON.parse(JSON.stringify(room.match)) as MatchState) : null;
  // A finished match is a record of who played and won: the seat keeps its name
  // (uid removed), and the result/settlement text is left as written. Labelling
  // it "Left player" made a fair winner look like a departed seat (GPLLGC).
  // The room itself is deleted FINISHED_RETENTION_MS after it finished.
  const finishedMatch = !!match && (room.status === "finished" || match.status === "finished");
  if (match) {
    const i = match.seats.findIndex((s) => s.uid === uid);
    if (i >= 0) {
      const s = match.seats[i];
      if (s.displayName) names.add(s.displayName);
      if (wasPlaying) {
        // Escrowed table bank is forfeited into the pot so the table stays whole for others.
        match.pot += s.bank; s.bank = 0;
        if (!s.eliminated) dropSeat(match, i);
      }
      s.uid = null as unknown as undefined;
      if (!finishedMatch) s.displayName = LEFT_NAME;
    }
    if (!finishedMatch && match.lastPayout?.message) {
      let msg = match.lastPayout.message;
      for (const n of names) msg = msg.split(n).join(LEFT_NAME);
      match.lastPayout.message = msg;
    }
  }
  if (room.hostUid === uid) {
    const next = match?.seats.find((s) => s.uid && !s.eliminated && memberUids.includes(s.uid))?.uid
      ?? memberUids[0] ?? null;
    fields.hostUid = next;
    if (room.status === "lobby") fields.status = "abandoned";
  }
  const freeCode = room.status === "lobby" && (room.hostUid === uid || memberUids.length === 0);
  return { deleteRoom: memberUids.length === 0, freeCode, fields, match, wasPlaying };
}

export type SweepAction = "autoplay" | "abandon" | "delete" | null;

/** What sweepRooms should do with a room at time `now` (ms). */
export function sweepAction(room: Room, now: number, lobbyIdleMs: number): SweepAction {
  const last = typeof room.lastActivity === "number" ? room.lastActivity : room.lastActivity?.toMillis?.() ?? 0;
  switch (room.status) {
    case "playing": return typeof room.turnDeadline === "number" && room.turnDeadline < now ? "autoplay" : null;
    case "lobby": return last < now - lobbyIdleMs ? "abandon" : null;
    case "finished": return last < now - FINISHED_RETENTION_MS ? "delete" : null;
    case "abandoned": return last < now - ABANDONED_RETENTION_MS ? "delete" : null;
    default: return null;
  }
}

/** Settlement line for a leftover pot: one survivor "goes to", else the proportional split. */
export function potNote(m: MatchState, pot: number, split: Array<[number, number]>): string {
  const nm = (i: number) => m.seats[i].displayName ?? `Seat ${i + 1}`;
  if (split.length === 1) return `Pot of ${pot} goes to ${nm(split[0][0])}.`;
  return `Pot of ${pot} returned by table bank: ${split.map(([i, amt]) => `${nm(i)} +${amt}`).join(", ")}.`;
}

/**
 * Finished match: split the leftover pot (settlePot) and append the
 * settlement line to lastPayout (the leave / end-match / final-roll line).
 */
export function settleFinishedPot(m: MatchState): Array<[number, number]> {
  const pot = m.pot;
  const split = settlePot(m);
  if (split.length) {
    const note = potNote(m, pot, split);
    m.lastPayout = m.lastPayout
      ? { ...m.lastPayout, message: `${m.lastPayout.message} ${note}` }
      : { message: note, kind: "none", amount: pot, seat: m.winnerSeat ?? split[0][0], dice: [] };
  }
  return split;
}

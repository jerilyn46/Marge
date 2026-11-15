/**
 * "Your turn" push notifications (FCM). Pure helpers (no Firebase imports),
 * unit-tested in test/push.test.ts; index.ts wires them to Admin SDK.
 *
 * Tokens live in pushTokens/{uid} (server-only: the catch-all rule denies
 * client reads/writes). Push goes out after the room transaction commits.
 */
import type { MatchState } from "./engine";

export const TURN_CHANNEL_ID = "marge_online_turns";
export const MAX_TOKENS_PER_USER = 5;
/** A turn lasts 60 s; a push that arrives much later is stale, so FCM drops it. */
export const TURN_PUSH_TTL_MS = 90_000;

export interface TurnSnap { seat: number; setNumber: number; rollNumber: number }

export interface TurnPush { uid: string; seat: number; roomId: string; code: string }

export function turnSnap(m: MatchState | null | undefined): TurnSnap | null {
  const t = m?.status === "playing" ? m.turn : null;
  return t ? { seat: t.seat, setNumber: t.setNumber, rollNumber: t.rollNumber } : null;
}

/**
 * Who (if anyone) should get "Your turn" after a match mutation.
 * - `before`: the turn before the action (null at match start).
 * - `after`: the committed match (bots already run).
 * - `actorUid`: the player who called the function; null for the
 *   sweepRooms timeout autoplay.
 * - `played`: the mutation was a roll/bank/autoplay (not a leave or delete).
 * The turn "passed" when the seat changed, or a play brought it all the way
 * back to the same seat as a fresh set (e.g. everyone else is a bot). A
 * scoring bank that keeps the seat (set 2+) is not a pass, and neither is a
 * leave that leaves the current turn untouched. Never bots, never the actor,
 * never an eliminated seat or a seat without a uid.
 */
export function turnPushRecipient(before: TurnSnap | null, after: MatchState,
  actorUid: string | null, roomId: string, code: unknown, played = true): TurnPush | null {
  const now = turnSnap(after);
  if (!now) return null;
  const freshSet = now.setNumber === 1 && now.rollNumber === 0;
  const beforeFresh = !!before && before.setNumber === 1 && before.rollNumber === 0;
  const passed = !before || before.seat !== now.seat || (freshSet && (played || !beforeFresh));
  if (!passed) return null;
  const s = after.seats[now.seat];
  if (!s || s.eliminated || !s.uid || (s.kind !== "host" && s.kind !== "human")) return null;
  if (actorUid && s.uid === actorUid) return null;
  return { uid: s.uid, seat: now.seat, roomId, code: typeof code === "string" ? code : "" };
}

export function turnPushText(code: string): { title: string; body: string } {
  return {
    title: code ? `Your turn in Marge (room ${code})` : "Your turn in Marge",
    body: "Tap to jump back to the table. You have 60 seconds to roll.",
  };
}

/** FCM multicast message for one recipient's tokens. */
export function turnPushMessage(p: TurnPush, tokens: string[]) {
  const { title, body } = turnPushText(p.code);
  return {
    tokens,
    notification: { title, body },
    data: { type: "turn", roomId: p.roomId, code: p.code },
    android: {
      priority: "high" as const,
      ttl: TURN_PUSH_TTL_MS,
      collapseKey: `turn-${p.roomId}`,
      notification: { channelId: TURN_CHANNEL_ID, tag: `turn-${p.roomId}` },
    },
  };
}

/** Token is gone for good: remove it from pushTokens/{uid}. */
const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export interface SendResult { success: boolean; error?: { code?: string } }

export function deadTokens(tokens: string[], responses: SendResult[]): string[] {
  return tokens.filter((_, i) => {
    const r = responses[i];
    return !!r && !r.success && !!r.error?.code && DEAD_TOKEN_CODES.has(r.error.code);
  });
}

/** New token list: newest first, deduped, `replaces` dropped, capped. */
export function mergeTokens(existing: unknown, token: string, replaces?: unknown): string[] {
  const old = Array.isArray(existing) ? existing.filter((t): t is string => typeof t === "string") : [];
  return [token, ...old.filter((t) => t !== token && t !== replaces)].slice(0, MAX_TOKENS_PER_USER);
}

export function validToken(t: unknown): t is string {
  return typeof t === "string" && t.length >= 20 && t.length <= 4096 && !/\s/.test(t);
}

export interface PushDeps {
  getTokens(uid: string): Promise<string[]>;
  send(msg: ReturnType<typeof turnPushMessage>): Promise<{ responses: SendResult[] }>;
  removeTokens(uid: string, dead: string[]): Promise<void>;
  log?(msg: string, extra?: Record<string, unknown>): void;
}

/** Send one turn push; prune dead tokens. Never throws (a push must not fail a move). */
export async function sendTurnPush(p: TurnPush | null, deps: PushDeps): Promise<{ sent: number; pruned: number }> {
  if (!p) return { sent: 0, pruned: 0 };
  try {
    const tokens = await deps.getTokens(p.uid);
    if (!tokens.length) return { sent: 0, pruned: 0 };
    const res = await deps.send(turnPushMessage(p, tokens));
    const dead = deadTokens(tokens, res.responses);
    if (dead.length) await deps.removeTokens(p.uid, dead);
    const sent = res.responses.filter((r) => r.success).length;
    const errors = [...new Set(res.responses.filter((r) => !r.success).map((r) => r.error?.code ?? "unknown"))];
    deps.log?.("turn push", { roomId: p.roomId, seat: p.seat, tokens: tokens.length, sent, pruned: dead.length, errors });
    return { sent, pruned: dead.length };
  } catch (e) {
    deps.log?.("turn push failed", { roomId: p.roomId, seat: p.seat, error: String((e as Error)?.message ?? e) });
    return { sent: 0, pruned: 0 };
  }
}

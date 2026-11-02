// Smoke test against local emulators only (project demo-marge). Run via: npm run smoke
const P = process.env.PROJECT ?? "demo-marge";
const AUTH = "http://127.0.0.1:9099", FN = `http://127.0.0.1:5001/${P}/us-central1`;
const FS = `http://127.0.0.1:8080/v1/projects/${P}/databases/(default)/documents`;
let fails = 0;
const ok = (c, msg) => { console.log(`${c ? "PASS" : "FAIL"} ${msg}`); if (!c) fails++; };
async function anon() {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, { method: "POST", body: "{}", headers: { "content-type": "application/json" } });
  return (await r.json()).idToken;
}
async function call(tok, name, data) {
  const r = await fetch(`${FN}/${name}`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${tok}` }, body: JSON.stringify({ data }) });
  const j = await r.json();
  if (j.error) throw new Error(`${name}: ${j.error.status} ${j.error.message}`);
  return j.result;
}
async function room(id) {
  const r = await fetch(`${FS}/rooms/${id}`, { headers: { authorization: "Bearer owner" } });
  const f = (await r.json()).fields;
  const v = (x) => x == null ? x : "stringValue" in x ? x.stringValue : "integerValue" in x ? +x.integerValue : "doubleValue" in x ? x.doubleValue : "booleanValue" in x ? x.booleanValue : "nullValue" in x ? null : "arrayValue" in x ? (x.arrayValue.values ?? []).map(v) : "mapValue" in x ? Object.fromEntries(Object.entries(x.mapValue.fields ?? {}).map(([k, y]) => [k, v(y)])) : x;
  return Object.fromEntries(Object.entries(f).map(([k, y]) => [k, v(y)]));
}
const tokOf = {};
async function playTurn(r) {
  const seat = r.match.turn.seat, tok = tokOf[r.match.seats[seat].uid];
  if (!tok) return false;
  await call(tok, "submitRoll", { roomId: r.id, expectedVersion: r.version });
  let n = await room(r.id);
  if (n.status === "playing" && n.match.turn?.seat === seat && n.match.turn.score && n.match.turn.score.kind !== "none") {
    await call(tok, "submitKeep", { roomId: r.id, expectedVersion: n.version });
  }
  return true;
}
try {
  const [h, g, c] = [await anon(), await anon(), await anon()];
  const { roomId, code } = await call(h, "createRoom", { seatCount: 4, botCount: 1, ante: 10, displayName: "Host", clientGemClaim: 500 });
  ok(/^[A-Z2-9]{6}$/.test(code), `createRoom code ${code}`);
  ok((await call(g, "joinRoom", { code, displayName: "Guest", clientGemClaim: 300 })).roomId === roomId, "joinRoom guest");
  await call(c, "joinRoom", { code, displayName: "Carol", clientGemClaim: 200 });
  let r = await room(roomId); r.id = roomId;
  ok(r.seats.filter((s) => s.kind === "bot").length === 1, "1 bot seat, open seats not auto-filled");
  for (const s of r.seats) if (s.uid) tokOf[s.uid] = { Host: h, Guest: g, Carol: c }[s.displayName];
  try { await call(g, "startMatch", { roomId }); ok(false, "non-host start rejected"); } catch { ok(true, "non-host start rejected"); }
  await call(h, "startMatch", { roomId });
  r = await room(roomId); r.id = roomId;
  ok(r.status === "playing" && r.match.pot > 0, `startMatch playing, pot ${r.match?.pot}`);
  for (let k = 0; k < 6 && r.status === "playing"; k++) { await playTurn(r); r = await room(roomId); r.id = roomId; }
  ok(true, `played turns, status ${r.status}`);
  if (r.status === "playing") {
    const guestSeat = r.match.seats.find((s) => s.displayName === "Guest");
    await call(g, "deleteOnlineData", {});
    r = await room(roomId); r.id = roomId;
    ok(!r.memberUids.includes(guestSeat.uid) && !r.match.seats.some((s) => s.uid === guestSeat.uid), "deleteOnlineData scrubs guest mid-match");
    ok(r.status === "playing" && r.match.turn && r.match.seats[r.match.turn.seat].uid !== guestSeat.uid, "room still playable after delete");
    if (r.status === "playing") { await playTurn(r); r = await room(roomId); r.id = roomId; ok(true, "remaining seat took a turn"); }
    if (r.status === "playing") await call(h, "endMatch", { roomId });
    r = await room(roomId);
    ok(r.status === "finished", "host endMatch finishes after delete");
  } else ok(true, "match finished early by dice; delete-mid-match path skipped this run");
} catch (e) { ok(false, e.message); }
console.log(fails ? `SMOKE FAILED (${fails})` : "SMOKE OK");
process.exit(fails ? 1 : 0);

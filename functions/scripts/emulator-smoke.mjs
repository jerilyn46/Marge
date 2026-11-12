// Smoke test against local emulators only (project demo-marge). Run via: npm run smoke
const P = process.env.PROJECT ?? "demo-marge";
const AUTH = "http://127.0.0.1:9099", FN = `http://127.0.0.1:5001/${P}/us-central1`;
const FS = `http://127.0.0.1:8080/v1/projects/${P}/databases/(default)/documents`;
let fails = 0;
const ok = (c, msg) => { console.log(`${c ? "PASS" : "FAIL"} ${msg}`); if (!c) fails++; };
async function anonU() {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, { method: "POST", body: "{}", headers: { "content-type": "application/json" } });
  const j = await r.json();
  return { tok: j.idToken, uid: j.localId };
}
async function anon() { return (await anonU()).tok; }
async function call(tok, name, data) {
  const r = await fetch(`${FN}/${name}`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${tok}` }, body: JSON.stringify({ data }) });
  const j = await r.json();
  if (j.error) throw new Error(`${name}: ${j.error.status} ${j.error.message}`);
  return j.result;
}
async function rawDoc(path) {
  const r = await fetch(`${FS}/${path}`, { headers: { authorization: "Bearer owner" } });
  return r.status === 404 ? null : (await r.json()).fields;
}
async function room(id) { return docOf(`rooms/${id}`); }
async function docOf(path) {
  const f = await rawDoc(path);
  if (!f) return null;
  const v = (x) => x == null ? x : "stringValue" in x ? x.stringValue : "integerValue" in x ? +x.integerValue : "doubleValue" in x ? x.doubleValue : "booleanValue" in x ? x.booleanValue : "nullValue" in x ? null : "arrayValue" in x ? (x.arrayValue.values ?? []).map(v) : "mapValue" in x ? Object.fromEntries(Object.entries(x.mapValue.fields ?? {}).map(([k, y]) => [k, v(y)])) : x;
  return Object.fromEntries(Object.entries(f).map(([k, y]) => [k, v(y)]));
}
const tokOf = {};
let gDeleted = false;
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
    await call(g, "deleteOnlineData", {}); gDeleted = true;
    r = await room(roomId); r.id = roomId;
    ok(!JSON.stringify(r).includes(guestSeat.uid) && !JSON.stringify(r).includes("Guest"), "deleteOnlineData scrubs guest uid+name everywhere mid-match");
    ok(r.status === "playing" && r.match.turn && r.match.seats[r.match.turn.seat].uid !== guestSeat.uid, "room still playable after delete");
    if (r.status === "playing") { await playTurn(r); r = await room(roomId); r.id = roomId; ok(true, "remaining seat took a turn"); }
    if (r.status === "playing") await call(h, "endMatch", { roomId });
    r = await room(roomId);
    ok(r.status === "finished" && r.match.pot === 0, `host endMatch finishes after delete, pot ${r.match.pot}`);
    const humans = r.match.seats.filter((s) => s.uid);
    const ug = await Promise.all(humans.map((s) => docOf(`users/${s.uid}`)));
    const botBank = r.match.seats.filter((s) => s.kind === "bot").reduce((a, s) => a + s.bank, 0);
    const tot = ug.reduce((a, u) => a + u.gems, 0) + botBank;
    ok(tot === 500 + 300 + 200 + 100 && humans.every((s, k) => ug[k].gems === s.bank), `gems conserved incl. forfeited guest: users ${ug.map((u) => u.gems)} + bot ${botBank} = ${tot}`);
  } else ok(true, "match finished early by dice; delete-mid-match path skipped this run");
  if (!gDeleted) await call(g, "deleteOnlineData", {});
  await call(h, "deleteOnlineData", {}); await call(c, "deleteOnlineData", {});
  ok((await room(roomId)) === null, "room 1 deleted once last human deletes data");

  // Host endMatch with gems in the pot: pot returned by table bank, totals conserved.
  const [X, Y] = [await anonU(), await anonU()];
  const r2 = await call(X.tok, "createRoom", { seatCount: 2, botCount: 0, ante: 10, displayName: "Xena", clientGemClaim: 60 });
  await call(Y.tok, "joinRoom", { code: r2.code, displayName: "Yuri", clientGemClaim: 40 });
  await call(X.tok, "startMatch", { roomId: r2.roomId });
  tokOf[X.uid] = X.tok; tokOf[Y.uid] = Y.tok;
  let q = await room(r2.roomId); q.id = r2.roomId;
  const potAtStart = q.match.pot;
  await call(X.tok, "endMatch", { roomId: r2.roomId });
  q = await room(r2.roomId);
  const [ux, uy] = [await docOf(`users/${X.uid}`), await docOf(`users/${Y.uid}`)];
  ok(q.status === "finished" && q.match.pot === 0 && potAtStart === 20, `endMatch: pot ${potAtStart} -> ${q.match.pot}: ${q.match.lastPayout?.message}`);
  ok(ux.gems + uy.gems === 100 && ux.gems === q.match.seats[0].bank && uy.gems === q.match.seats[1].bank && !ux.escrowRoom && !uy.escrowRoom,
    `endMatch conserves: users ${ux.gems}+${uy.gems} = 100, escrow cleared`);
  // Finished room: deleting one player anonymizes; last player deletes the room.
  await call(Y.tok, "deleteOnlineData", {});
  q = await room(r2.roomId);
  ok(q && !JSON.stringify(q).includes(Y.uid) && !JSON.stringify(q).includes("Yuri") && q.memberUids.length === 1, "finished room scrubbed of deleted player (uid + name)");
  await call(X.tok, "deleteOnlineData", {});
  ok((await room(r2.roomId)) === null, "finished room deleted when last member deletes data");

  // Lone lobby host deletes: room + code gone.
  const Z = await anonU();
  const r3 = await call(Z.tok, "createRoom", { seatCount: 2, botCount: 0, ante: 10, displayName: "Zed", clientGemClaim: 50 });
  await call(Z.tok, "deleteOnlineData", {});
  const W = await anon();
  let codeGone = false; try { await call(W, "joinRoom", { code: r3.code }); } catch (e) { codeGone = /not.found/i.test(e.message); }
  ok((await room(r3.roomId)) === null && codeGone, "lobby room + code deleted when lone host deletes data");
  await call(W, "deleteOnlineData", {});
} catch (e) { ok(false, e.message); }
console.log(fails ? `SMOKE FAILED (${fails})` : "SMOKE OK");
process.exit(fails ? 1 : 0);

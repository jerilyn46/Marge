// Live probe for "Your turn" pushes (no device needed). Two anonymous clients;
// the guest registers a FAKE FCM token, the host starts a 2-seat match and plays
// until the turn passes to the guest, so the server attempts a push to the fake
// token. Then: the token should be pruned from pushTokens/{uid} (FCM said
// "invalid/not registered" = FCM API + credentials work), or it stays (check
// `firebase functions:log` for the "turn push" errors list). Cleans up with
// deleteOnlineData. No secrets in this file: config comes from env.
//   GOOGLE_SERVICES_JSON=/path/to/google-services.json node push-probe.mjs
import { readFileSync } from "node:fs";
import { initializeApp } from "firebase/app";
import { getAuth, signInAnonymously } from "firebase/auth";
import { getFunctions, httpsCallable } from "firebase/functions";
import { getFirestore, doc, getDocFromServer } from "firebase/firestore";

const g = JSON.parse(readFileSync(process.env.GOOGLE_SERVICES_JSON, "utf8"));
const c0 = g.client[0];
const CONFIG = { apiKey: c0.api_key[0].current_key, projectId: g.project_info.project_id,
  appId: c0.client_info.mobilesdk_app_id, messagingSenderId: g.project_info.project_number };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let n = 0;
async function client() {
  const app = initializeApp(CONFIG, `probe-${n++}`);
  const cred = await signInAnonymously(getAuth(app));
  const fns = getFunctions(app, "us-central1");
  return { uid: cred.user.uid, db: getFirestore(app), call: async (name, data) => (await httpsCallable(fns, name)(data)).data };
}
const H = await client(), G = await client();
try {
  await G.call("registerPushToken", { token: `probe-fake-token-${"x".repeat(60)}` });
  const { roomId, code } = await H.call("createRoom", { seatCount: 2, botCount: 0, ante: 10, displayName: "Probe Host", clientGemClaim: 100 });
  await G.call("joinRoom", { code, displayName: "Probe Guest", clientGemClaim: 100 });
  await H.call("startMatch", { roomId });
  for (let i = 0; i < 6; i++) {
    const r = (await getDocFromServer(doc(H.db, "rooms", roomId))).data();
    if (r.status !== "playing" || r.match.turn.seat !== 0) break;
    const t = r.match.turn;
    if (t.rollNumber > 0 && t.score && t.score.kind !== "none") await H.call("submitKeep", { roomId, expectedVersion: r.version });
    else await H.call("submitRoll", { roomId, expectedVersion: r.version });
  }
  const r = (await getDocFromServer(doc(H.db, "rooms", roomId))).data();
  console.log(`room ${code}: status ${r.status}, turn seat ${r.match?.turn?.seat}, rollSeq ${r.match?.rollSeq}`);
  await sleep(2000);
  console.log("now check: firebase functions:log | grep 'turn push' (errors should be messaging/invalid-registration-token or registration-token-not-registered → pruned)");
} finally {
  await G.call("deleteOnlineData", {}).catch((e) => console.log("G delete", e.message));
  await H.call("deleteOnlineData", {}).catch((e) => console.log("H delete", e.message));
  process.exit(0);
}

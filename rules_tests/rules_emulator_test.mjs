// Rules simulation against the Firestore emulator, using the real firestore.rules.
// No new packages: Node's built-in fetch only.
// Run: firebase emulators:start --only firestore --project demo-ers  (in another terminal)
//      node rules_tests/rules_emulator_test.mjs
const HOST = 'http://127.0.0.1:8080';
const PROJECT = 'demo-ers';
const BASE = `${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(uid, role) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: 'none', typ: 'JWT' });
  const payload = b64({
    sub: uid, user_id: uid, role,
    aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: now, exp: now + 3600, auth_time: now,
    firebase: { identities: {}, sign_in_provider: 'custom' },
  });
  return `${header}.${payload}.`;
}

const AS = {
  owner: { authorization: 'Bearer owner' },
  admin: { authorization: `Bearer ${token('admin1', 'SystemAdmin')}` },
  resident1: { authorization: `Bearer ${token('res1', 'Resident')}` },
  resident2: { authorization: `Bearer ${token('res2', 'Resident')}` },
  responder1: { authorization: `Bearer ${token('r1', 'Responder')}` },
  responder2: { authorization: `Bearer ${token('r2', 'Responder')}` },
  dispatcher: { authorization: `Bearer ${token('disp1', 'Dispatcher')}` },
};

const S = (v) => ({ stringValue: v });
const I = (v) => ({ integerValue: String(v) });
const D = (v) => ({ doubleValue: v });
const BOOL = (v) => ({ booleanValue: v });
const TS = (v = '2026-10-29T12:00:00Z') => ({ timestampValue: v });
const GEO = (lat, lng) => ({ geoPointValue: { latitude: lat, longitude: lng } });
const MAP = (fields) => ({ mapValue: { fields } });

async function req(method, path, body, auth, query = '') {
  const res = await fetch(`${BASE}/${path}${query}`, {
    method,
    headers: { 'content-type': 'application/json', ...auth },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, text };
}

const get = (path, auth) => req('GET', path, undefined, auth);
const del = (path, auth) => req('DELETE', path, undefined, auth);
const patch = (path, fields, mask, auth) =>
  req('PATCH', path, { fields }, auth,
    '?' + mask.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&'));
async function create(collection, id, fields, auth) {
  const r = await req('POST', collection, { fields }, auth, `?documentId=${encodeURIComponent(id)}`);
  if (auth === AS.owner && r.status !== 200) throw new Error(`seed ${collection}/${id} -> ${r.status} ${r.text}`);
  return r;
}
async function commit(writes, auth) {
  const res = await fetch(`${HOST}/v1/projects/${PROJECT}/databases/(default)/documents:commit`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...auth },
    body: JSON.stringify({ writes }),
  });
  return { status: res.status, text: await res.text() };
}
const docName = (path) => `projects/${PROJECT}/databases/(default)/documents/${path}`;

let pass = 0, fail = 0;
const results = [];
function check(label, expected, actual, extra = '') {
  const ok = actual === expected;
  ok ? pass++ : fail++;
  results.push(`${ok ? 'PASS' : 'FAIL'}  ${label}  (expected ${expected}, got ${actual}${extra ? ', ' + extra : ''})`);
}

// ------------------------------------------------------------------ seed (Admin SDK equivalent: owner bypass)
async function seed() {
  const incident = (userId, status) => ({
    userId: S(userId), category: S('Medical Emergency'), status: S(status),
    location: GEO(-1.2921, 36.8219), createdAt: TS(), updatedAt: TS(),
    priority: S('High'), prioritySource: S('safe_fallback'), needsHumanReview: BOOL(true),
    triageStatus: S('pending'), landmark: S(''), locationAccuracyM: D(10),
    locationSource: S('gps'),
  });
  await create('incidents', 'i1', incident('res1', 'Active'), AS.owner);
  await create('incidents', 'i2', incident('res1', 'Resolved'), AS.owner);

  await create('users', 'res1', {
    userId: S('res1'), firstName: S('A'), lastName: S('B'), dateOfBirth: TS('1990-01-01T00:00:00Z'),
    gender: S('Other'), phoneNumber: S('+254700000001'), email: S('res1@example.test'),
    role: S('Resident'), preferredLanguage: S('en'), accountStatus: S('Active'),
    consentCrossBorderTransfer: BOOL(true), createdAt: TS(), updatedAt: TS(), lastLoginAt: TS(),
  }, AS.owner);

  await create('facilities', 'F1', { name: S('Aga Khan Hospital'), type: S('Hospital') }, AS.owner);

  const offer = (responderId, status) => ({
    incidentId: S('i1'), responderId: S(responderId), status: S(status),
    expiresAt: TS('2026-11-02T00:00:00Z'),
  });
  await create('offers', 'o_seen', offer('r1', 'offered'), AS.owner);
  await create('offers', 'o_other', offer('r2', 'offered'), AS.owner);
  await create('offers', 'o_transport', offer('r1', 'arrived'), AS.owner);
  await create('offers', 'o_transport_early', offer('r1', 'enroute'), AS.owner);
  await create('offers', 'o_transport_bad', offer('r1', 'arrived'), AS.owner);
  await create('offers', 'o_more', offer('r1', 'accepted'), AS.owner);
  await create('offers', 'o_steps', offer('r1', 'offered'), AS.owner);
  await create('offers', 'o_route', offer('r1', 'accepted'), AS.owner);
  await create('offers', 'i1_r1', offer('r1', 'accepted'), AS.owner);

  await create('incidents/i1/events', 'E1', { type: S('offer_sent'), actorRole: S('system') }, AS.owner);
  await create('sos_alerts', 'S1', { responderId: S('r1'), status: S('open') }, AS.owner);
  await create('incidents/i1/private', 'contact', { phone: S('+254700000009') }, AS.owner);
}

// ------------------------------------------------------------------ cases
async function cases() {
  // 1. Resident reads own incident: allowed; another resident's: denied.
  check('1a resident reads own incident', 200, (await get('incidents/i1', AS.resident1)).status);
  check('1b resident reads another resident\'s incident', 403, (await get('incidents/i1', AS.resident2)).status);

  // 2. Nobody (resident, responder, admin) reads private/contact.
  for (const [who, auth] of [['resident', AS.resident1], ['responder', AS.responder1], ['admin', AS.admin]]) {
    check(`2 ${who} reads incidents/i1/private/contact`, 403, (await get('incidents/i1/private/contact', auth)).status);
  }

  // 3. seenAt on own offer allowed; on someone else's denied.
  check('3a responder writes seenAt on own offer', 200,
    (await patch('offers/o_seen', { seenAt: TS() }, ['seenAt'], AS.responder1)).status);
  check('3b responder writes seenAt on another responder\'s offer', 403,
    (await patch('offers/o_other', { seenAt: TS() }, ['seenAt'], AS.responder1)).status);

  // 4. transport: valid facility after arrival allowed; before arrival denied; extra keys denied.
  const goodTransport = { destinationId: S('F1'), destinationName: S('Aga Khan Hospital'), startedAt: TS() };
  check('4a responder writes transport after arrival with a real facility', 200,
    (await patch('offers/o_transport', { transport: MAP(goodTransport) }, ['transport'], AS.responder1)).status);
  check('4b responder writes transport before arrival', 403,
    (await patch('offers/o_transport_early', { transport: MAP(goodTransport) }, ['transport'], AS.responder1)).status);
  check('4c responder writes transport with an extra key', 403,
    (await patch('offers/o_transport_bad',
      { transport: MAP({ ...goodTransport, etaMinutes: I(4) }) }, ['transport'], AS.responder1)).status);

  // 5. moreUnits: count 2 once allowed; count 4 denied; second write denied.
  const more = (count, note) => MAP({ role: S('fire_suppression'), count: I(count), note: S(note) });
  const moreWrite = (offerPath, map) => commit([{
    update: { name: docName(offerPath), fields: { moreUnits: map } },
    updateMask: { fieldPaths: ['moreUnits.role', 'moreUnits.count', 'moreUnits.note'] },
    updateTransforms: [{ fieldPath: 'moreUnits.requestedAt', setToServerValue: 'REQUEST_TIME' }],
  }], AS.responder1);
  const first = await moreWrite('offers/o_more', more(2, 'fire spreading'));
  check('5a responder writes moreUnits count 2 once', 200, first.status, first.status !== 200 ? first.text.slice(0, 120) : '');
  check('5b responder writes moreUnits count 4', 403,
    (await moreWrite('offers/o_route', more(4, 'too many'))).status);
  check('5c responder writes moreUnits a second time', 403,
    (await moreWrite('offers/o_more', more(1, 'again'))).status);

  // 6. status steps cannot skip; routing fields cannot be written.
  check('6a responder skips offered -> arrived', 403,
    (await patch('offers/o_steps', { status: S('arrived'), respondedAt: TS(), updatedAt: TS() },
      ['status', 'respondedAt', 'updatedAt'], AS.responder1)).status);
  check('6b responder writes a routing field on an offer', 403,
    (await patch('offers/o_route', { etaMinutes: I(4) }, ['etaMinutes'], AS.responder1)).status);
  check('6c responder writes route on an offer', 403,
    (await patch('offers/o_route', { route: S('{}') }, ['route'], AS.responder1)).status);

  // 7. resident landmark: 120 while Active allowed; 121 denied; after Resolved denied.
  check('7a resident writes landmark of 120 chars while Active', 200,
    (await patch('incidents/i1', { landmark: S('L'.repeat(120)), updatedAt: TS() }, ['landmark', 'updatedAt'], AS.resident1)).status);
  check('7b resident writes landmark of 121 chars', 403,
    (await patch('incidents/i1', { landmark: S('L'.repeat(121)), updatedAt: TS() }, ['landmark', 'updatedAt'], AS.resident1)).status);
  check('7c resident writes landmark after the incident closed', 403,
    (await patch('incidents/i2', { landmark: S('gate'), updatedAt: TS() }, ['landmark', 'updatedAt'], AS.resident1)).status);

  // 8. residentFeedback once when Resolved; twice denied; while Active denied.
  check('8a resident writes residentFeedback once when Resolved', 200,
    (await patch('incidents/i2', { residentFeedback: MAP({ safe: BOOL(true) }), updatedAt: TS() },
      ['residentFeedback', 'updatedAt'], AS.resident1)).status);
  check('8b resident writes residentFeedback twice', 403,
    (await patch('incidents/i2', { residentFeedback: MAP({ safe: BOOL(false) }), updatedAt: TS() },
      ['residentFeedback', 'updatedAt'], AS.resident1)).status);
  check('8c resident writes residentFeedback while Active', 403,
    (await patch('incidents/i1', { residentFeedback: MAP({ safe: BOOL(true) }), updatedAt: TS() },
      ['residentFeedback', 'updatedAt'], AS.resident1)).status);

  // 9. admin reads events and sos_alerts allowed; resident, responder, older Dispatcher denied.
  check('9a admin reads incidents/i1/events/E1', 200, (await get('incidents/i1/events/E1', AS.admin)).status);
  check('9b admin reads sos_alerts/S1', 200, (await get('sos_alerts/S1', AS.admin)).status);
  for (const [who, auth] of [['resident', AS.resident1], ['responder', AS.responder1], ['older Dispatcher', AS.dispatcher]]) {
    check(`9c ${who} reads incidents/i1/events/E1`, 403, (await get('incidents/i1/events/E1', auth)).status);
    check(`9d ${who} reads sos_alerts/S1`, 403, (await get('sos_alerts/S1', auth)).status);
  }

  // 10. clients cannot write events, sos_alerts or needsAttention.
  check('10a resident writes an event', 403,
    (await create('incidents/i1/events', 'EFORGED', { type: S('forged') }, AS.resident1)).status);
  check('10b admin writes an event', 403,
    (await create('incidents/i1/events', 'EFORGED2', { type: S('forged') }, AS.admin)).status);
  check('10c responder writes a sos_alert', 403,
    (await create('sos_alerts', 'SFORGED', { status: S('open') }, AS.responder1)).status);
  check('10d admin writes a sos_alert', 403,
    (await create('sos_alerts', 'SFORGED2', { status: S('open') }, AS.admin)).status);
  check('10e resident writes needsAttention on own incident', 403,
    (await patch('incidents/i1', { needsAttention: BOOL(true), updatedAt: TS() },
      ['needsAttention', 'updatedAt'], AS.resident1)).status);
  check('10f admin writes needsAttention on an incident', 403,
    (await patch('incidents/i1', { needsAttention: BOOL(true), updatedAt: TS() },
      ['needsAttention', 'updatedAt'], AS.admin)).status);

  // 11. preferredLanguage en/sw allowed; anything else denied.
  check('11a resident sets preferredLanguage sw', 200,
    (await patch('users/res1', { preferredLanguage: S('sw'), updatedAt: TS() },
      ['preferredLanguage', 'updatedAt'], AS.resident1)).status);
  check('11b resident sets preferredLanguage en', 200,
    (await patch('users/res1', { preferredLanguage: S('en'), updatedAt: TS() },
      ['preferredLanguage', 'updatedAt'], AS.resident1)).status);
  check('11c resident sets preferredLanguage fr', 403,
    (await patch('users/res1', { preferredLanguage: S('fr'), updatedAt: TS() },
      ['preferredLanguage', 'updatedAt'], AS.resident1)).status);

  // 12. tracks: owner/holder write allowed; others denied; deletion denied.
  const point = { lat: D(-1.2921), lng: D(36.8219), at: TS() };
  check('12a resident writes their own track while Active', 200,
    (await create('incidents/i1/tracks', 'res1', point, AS.resident1)).status);
  check('12b holding responder writes their own track', 200,
    (await create('incidents/i1/tracks', 'r1', point, AS.responder1)).status);
  check('12c non-holding responder writes a track', 403,
    (await create('incidents/i1/tracks', 'r2', point, AS.responder2)).status);
  check('12d resident writes the responder\'s track', 403,
    (await patch('incidents/i1/tracks/r1', point, ['lat', 'lng', 'at'], AS.resident1)).status);
  check('12e responder deletes their own track', 403,
    (await del('incidents/i1/tracks/r1', AS.responder1)).status);
  check('12f resident deletes their own track', 403,
    (await del('incidents/i1/tracks/res1', AS.resident1)).status);
}

try {
  await seed();
  await cases();
} catch (e) {
  console.error('SCRIPT ERROR:', e);
  fail++;
}
for (const line of results) console.log(line);
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);

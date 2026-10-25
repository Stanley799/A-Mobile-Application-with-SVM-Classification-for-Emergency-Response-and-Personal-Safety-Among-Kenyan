const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const test = require('node:test');

const host = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!host || !projectId?.startsWith('demo-')) {
  throw new Error('Run these tests with the Firestore emulator and a demo- project.');
}
const documentsUrl = `http://${host}/v1/projects/${projectId}/databases/(default)/documents`;

function tokenFor(userId) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    iss: `https://securetoken.google.com/${projectId}`,
    aud: projectId,
    sub: userId,
    user_id: userId,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    firebase: { sign_in_provider: 'custom', identities: {} },
  })).toString('base64url');
  return `${header}.${payload}.`;
}

function fieldValue(value) {
  if (value === null) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(fieldValue) } };
  return { mapValue: { fields: fieldsFor(value) } };
}

function fieldsFor(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, fieldValue(value)]));
}

function incidentData(activationPath, overrides = {}) {
  return {
    reporterId: 'resident',
    userId: 'resident',
    activationPath,
    category: activationPath === 'sos_button' ? 'Unknown' : 'Medical Emergency',
    priority: activationPath === 'sos_button' ? 'PendingHumanTriage' : 'Medium',
    classifierConfidence: 0.7,
    triageAnswers: {},
    status: 'New',
    channel: 'internet',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  };
}

async function writeIncident(id, data, userId = 'resident', update = false) {
  const mask = update
    ? `?${Object.keys(data).map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`).join('&')}`
    : '';
  return fetch(`${documentsUrl}/incidents/${id}${mask}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      ...(userId ? { Authorization: `Bearer ${tokenFor(userId)}` } : {}),
    },
    body: JSON.stringify({ fields: fieldsFor(data) }),
  });
}

for (const activationPath of ['sos_button', 'category_selection', 'other_free_text']) {
  test(`${activationPath}: accepts omitted optional fields and owner cancellation`, async () => {
    const id = randomUUID();
    const data = incidentData(activationPath, activationPath === 'other_free_text'
      ? { freeTextDescription: 'An incident without recognized keywords' }
      : { triageAnswers: { conscious: 'Unknown', severeBleeding: null, chestPain: false } });
    const created = await writeIncident(id, data);
    assert.equal(created.status, 200, await created.text());
    const cancelled = await writeIncident(id, {
      status: 'Cancelled', updatedAt: new Date(),
    }, 'resident', true);
    assert.equal(cancelled.status, 200, await cancelled.text());
  });
}

test('rejects signed-out creation and another reporter identity', async () => {
  const unauthenticated = await writeIncident(randomUUID(), incidentData('sos_button'), null);
  assert.equal(unauthenticated.status, 403, await unauthenticated.text());
  const impersonated = await writeIncident(randomUUID(), incidentData('sos_button'), 'attacker');
  assert.equal(impersonated.status, 403, await impersonated.text());
});

test('rejects another user cancelling and owner changing incident details', async () => {
  const id = randomUUID();
  const created = await writeIncident(id, incidentData('category_selection'));
  assert.equal(created.status, 200, await created.text());
  const unauthorized = await writeIncident(id, {
    status: 'Cancelled', updatedAt: new Date(),
  }, 'attacker', true);
  assert.equal(unauthorized.status, 403, await unauthorized.text());
  const modified = await writeIncident(id, {
    status: 'Cancelled', category: 'Fire & Rescue', updatedAt: new Date(),
  }, 'resident', true);
  assert.equal(modified.status, 403, await modified.text());
});

test('rejects wrong types for optional fields', async () => {
  for (const invalid of [
    { latitude: 'not a coordinate' },
    { longitude: 'not a coordinate' },
    { freeTextDescription: false },
    { nlpExtractedKeywords: 'not a list' },
    { dispatchedAt: 'not a timestamp' },
    { responderId: 42 },
  ]) {
    const response = await writeIncident(randomUUID(), incidentData('sos_button', invalid));
    assert.equal(response.status, 403, await response.text());
  }
});
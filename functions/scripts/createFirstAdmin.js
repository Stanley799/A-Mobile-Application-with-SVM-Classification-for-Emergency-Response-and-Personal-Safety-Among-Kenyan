const { initializeApp, cert, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const fs = require("node:fs");
const path = require("node:path");

function resolveCredentials() {
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyPath) {
    const absolutePath = path.resolve(process.cwd(), keyPath);
    if (!fs.existsSync(absolutePath)) {
      throw new Error(`Service account key not found at ${absolutePath}`);
    }
    const serviceAccount = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
    return cert(serviceAccount);
  }
  return applicationDefault();
}

initializeApp({ credential: resolveCredentials() });

const db = getFirestore();

async function findExistingSystemAdmin() {
  const adminsByRole = await db.collection("users").where("role", "==", "SystemAdmin").limit(1).get();
  if (!adminsByRole.empty) {
    return adminsByRole.docs[0].id;
  }

  let nextPageToken;
  do {
    const result = await getAuth().listUsers(1000, nextPageToken);
    for (const user of result.users) {
      if (user.customClaims?.role === "SystemAdmin") {
        return user.uid;
      }
    }
    nextPageToken = result.pageToken;
  } while (nextPageToken);

  return null;
}

async function createFirstAdmin() {
  const existingAdminId = await findExistingSystemAdmin();
  if (existingAdminId) {
    throw new Error(`A SystemAdmin already exists (${existingAdminId}). This script must run only once.`);
  }

  const email = process.env.ADMIN_EMAIL;
  const password = process.env.ADMIN_PASSWORD;
  const firstName = process.env.ADMIN_FIRST_NAME || "System";
  const lastName = process.env.ADMIN_LAST_NAME || "Administrator";
  const phoneNumber = process.env.ADMIN_PHONE_NUMBER;
  const preferredLanguage = process.env.ADMIN_PREFERRED_LANGUAGE || "en";
  const gender = process.env.ADMIN_GENDER || "PreferNotToSay";
  const dobIso = process.env.ADMIN_DOB_ISO || "1990-01-01";

  if (!email || !password || !phoneNumber) {
    throw new Error("Missing required env vars: ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_PHONE_NUMBER");
  }

  if (!/^\+254[17]\d{8}$/.test(phoneNumber)) {
    throw new Error("ADMIN_PHONE_NUMBER must match ^\\+254[17]\\d{8}$");
  }

  if (preferredLanguage !== "en" && preferredLanguage !== "sw") {
    throw new Error("ADMIN_PREFERRED_LANGUAGE must be either 'en' or 'sw'");
  }

  const dateOfBirth = new Date(dobIso);
  if (Number.isNaN(dateOfBirth.getTime())) {
    throw new Error("ADMIN_DOB_ISO must be a valid ISO date, e.g. 1990-01-01");
  }

  const userRecord = await getAuth().createUser({
    email,
    password,
    phoneNumber,
    displayName: `${firstName} ${lastName}`,
  });

  await getAuth().setCustomUserClaims(userRecord.uid, { role: "SystemAdmin" });

  await db.collection("users").doc(userRecord.uid).set({
    userId: userRecord.uid,
    firstName,
    lastName,
    dateOfBirth,
    gender,
    phoneNumber,
    email,
    role: "SystemAdmin",
    preferredLanguage,
    accountStatus: "Active",
    consentCrossBorderTransfer: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    lastLoginAt: FieldValue.serverTimestamp(),
  });

  const auditRef = db.collection("auditLogs").doc();
  await auditRef.set({
    logId: auditRef.id,
    timestamp: FieldValue.serverTimestamp(),
    userId: userRecord.uid,
    action: "ROLE_CLAIM_SET",
    targetId: userRecord.uid,
    details: {
      role: "SystemAdmin",
      source: "createFirstAdmin",
    },
    previousState: null,
  });

  console.log(`SystemAdmin created successfully: ${userRecord.uid}`);
}

createFirstAdmin().catch((error) => {
  console.error(error.message);
  process.exit(1);
});

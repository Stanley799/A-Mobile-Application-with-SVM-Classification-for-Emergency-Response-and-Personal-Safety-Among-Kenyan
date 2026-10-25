const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

initializeApp();

const db = getFirestore();

async function writeAuditLog({ userId, action, targetId, details, previousState = null }) {
  // Admin SDK writes bypass client rules; clients cannot create or alter audit entries.
  const auditRef = db.collection("auditLogs").doc();
  await auditRef.set({
    logId: auditRef.id,
    timestamp: FieldValue.serverTimestamp(),
    userId,
    action,
    targetId,
    details,
    previousState,
  });
}

/** Copies a newly registered user's role into Firebase Auth custom claims. */
exports.setUserRoleClaim = onDocumentCreated("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const userData = event.data?.data();

  if (!userData || !userData.role) {
    logger.error("Missing role on users document", { userId });
    return;
  }

  const role = userData.role;

  await getAuth().setCustomUserClaims(userId, { role });

  await writeAuditLog({
    userId,
    action: "ROLE_CLAIM_SET",
    targetId: userId,
    details: {
      role,
      source: "setUserRoleClaim",
    },
  });

  logger.info("Custom role claim set", { userId, role });
});

/** Records the initial role, account state, and language for each new user. */
exports.logUserRegistration = onDocumentCreated("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const userData = event.data?.data();

  if (!userData) {
    logger.warn("No user data found for registration log", { userId });
    return;
  }

  await writeAuditLog({
    userId,
    action: "USER_REGISTERED",
    targetId: userId,
    details: {
      role: userData.role,
      accountStatus: userData.accountStatus,
      preferredLanguage: userData.preferredLanguage,
    },
  });

  logger.info("User registration logged", { userId });
});

/** Audits verification outcomes while ignoring unrelated responder updates. */
exports.logResponderVerificationChange = onDocumentUpdated(
  "responders/{responderId}",
  async (event) => {
    const responderId = event.params.responderId;
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();

    if (!beforeData || !afterData) {
      return;
    }

    const beforeStatus = beforeData.verificationStatus;
    const afterStatus = afterData.verificationStatus;

    if (beforeStatus === afterStatus) {
      return;
    }

    let action;
    if (afterStatus === "Verified") {
      action = "RESPONDER_VERIFIED";
    } else if (afterStatus === "Rejected") {
      action = "RESPONDER_REJECTED";
    } else if (afterStatus === "Suspended") {
      action = "RESPONDER_SUSPENDED";
    } else {
      return;
    }

    await writeAuditLog({
      userId: afterData.verifiedBy || "SYSTEM",
      action,
      targetId: responderId,
      details: {
        verificationStatus: afterStatus,
        verificationNotes: afterData.verificationNotes || null,
        verifiedBy: afterData.verifiedBy || null,
        verifiedAt: afterData.verifiedAt || null,
      },
      previousState: {
        verificationStatus: beforeStatus,
        verificationNotes: beforeData.verificationNotes || null,
        verifiedBy: beforeData.verifiedBy || null,
        verifiedAt: beforeData.verifiedAt || null,
      },
    });

    logger.info("Responder verification status change logged", {
      responderId,
      beforeStatus,
      afterStatus,
    });
  },
);

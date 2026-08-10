/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldPath, FieldValue} = require("firebase-admin/firestore");
const communicationEngine = require("./communication-engine");
const {resolveBusinessAuthority, hasBusinessPermission} = require("./business-authority");

const BUSINESS_ROLES = new Set([
  "owner",
  "admin",
  "manager",
  "operations",
  "dispatcher",
  "finance",
  "viewer",
  "member",
]);
const BUSINESS_ADMIN_ROLES = new Set(["owner", "admin", "manager"]);

function requireAuth(context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in to use Circum Business.",
    );
  }
  return uid;
}

function clean(value, fallback = "") {
  return `${value || fallback}`.trim();
}

function cleanEmail(value) {
  return clean(value).toLowerCase();
}

function slug(value, fallback = "business") {
  const normalised = clean(value)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 64);
  return normalised || fallback;
}

async function requireBusinessAdmin(db, businessId, context) {
  const uid = requireAuth(context);
  const email = cleanEmail(context.auth.token.email);
  const ref = db.collection("businessAccounts").doc(businessId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError(
        "not-found",
        "Business workspace not found.",
    );
  }
  const account = snap.data() || {};
  const authority = await resolveBusinessAuthority(db, account, businessId, {uid, email});
  const role = authority.role;
  if (!BUSINESS_ADMIN_ROLES.has(role)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Business owner, admin, or manager access is required.",
    );
  }
  return {uid, ref, account, role};
}

async function requireBusinessAction(db, businessId, context, permission) {
  const uid = requireAuth(context);
  const email = cleanEmail(context.auth.token.email);
  const ref = db.collection("businessAccounts").doc(businessId);
  const snap = await ref.get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  const account = snap.data() || {};
  const authority = await resolveBusinessAuthority(db, account, businessId, {uid, email});
  if (!hasBusinessPermission(authority, permission, ["owner", "admin", "manager"])) {
    throw new functions.https.HttpsError("permission-denied", "This Business role cannot perform that action.");
  }
  return {uid, ref, account, role: authority.role, authority};
}

function numericCode() {
  const length = Math.random() < 0.5 ? 8 : 9;
  let out = "";
  for (let i = 0; i < length; i += 1) out += Math.floor(Math.random() * 10);
  if (out[0] === "0") {
    out = `${Math.floor(Math.random() * 9) + 1}${out.slice(1)}`;
  }
  return out;
}

async function reserveCompanyCode(db, businessId, uid) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const code = numericCode();
    const ref = db.collection("businessCompanyCodes").doc(code);
    const reserved = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.set(ref, {
        businessId,
        companyCode: code,
        ownerUid: uid,
        status: "active",
        createdAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (reserved) return code;
  }
  throw new functions.https.HttpsError(
      "resource-exhausted",
      "A unique company code could not be generated. Try again.",
  );
}

function accountProjection(id, account, authority, irisMoments = [], teamMembers = []) {
  const managesTeam = ["owner", "admin", "manager"].includes(authority.role);
  return {
    id,
    businessName: account.businessName || "Business",
    status: account.status || "pending",
    approvalStatus: account.approvalStatus || account.status || "pending",
    businessAddress: account.businessAddress || "",
    companyNumber: account.companyNumber || "",
    companyCode: account.companyCode || "",
    connectedProducts: Array.isArray(account.connectedProducts) ? account.connectedProducts.slice(0, 20) : [],
    defaultPickupAddresses: Array.isArray(account.defaultPickupAddresses) ? account.defaultPickupAddresses.slice(0, 10) : [],
    contactName: managesTeam ? account.contactName || "" : "",
    contactEmail: managesTeam ? account.contactEmail || "" : "",
    phone: managesTeam ? account.phone || "" : "",
    billingEmail: authority.financialAuthorized ? account.billingEmail || "" : "",
    paymentPreferences: authority.financialAuthorized ? account.paymentPreferences || {} : {},
    notificationPreferences: account.notificationPreferences || {},
    teamMembers: managesTeam ? teamMembers.slice(0, 250) : [],
    recognitions: account.recognitions || {},
    irisMoments,
    role: authority.role,
  };
}

exports.listBusinessAccounts = functions.runWith({enforceAppCheck: true})
    .region("us-central1").https.onCall(async (_data, context) => {
      const uid = requireAuth(context);
      const email = cleanEmail(context.auth.token.email);
      const db = getFirestore();
      const snapshots = await Promise.all([
        db.collection("businessMemberships").where("userId", "==", uid).where("status", "==", "active").limit(50).get(),
        ...(email ? [db.collection("businessMemberships").where("email", "==", email).where("status", "==", "active").limit(50).get()] : []),
      ]);
      const accounts = new Map();
      snapshots.forEach((snapshot) => snapshot.docs.forEach((doc) => accounts.set(doc.data().businessId, null)));
      const projected = [];
      for (const id of accounts.keys()) {
        const accountSnap = await db.collection("businessAccounts").doc(id).get();
        if (!accountSnap.exists) continue;
        const account = accountSnap.data() || {};
        const authority = await resolveBusinessAuthority(db, account, id, {uid, email});
        if (authority.member) {
          const [moments, members] = await Promise.all([
            db.collection("businessAccounts").doc(id).collection("irisMoments").orderBy("recordedAt", "desc").limit(20).get(),
            authority.ownerOrAdmin ? db.collection("businessMemberships").where("businessId", "==", id).limit(250).get() : Promise.resolve({docs: []}),
          ]);
          projected.push(accountProjection(id, account, authority, moments.docs.map((doc) => ({
            id: doc.id,
            ...doc.data(),
            recordedAtMillis: doc.data().recordedAt && typeof doc.data().recordedAt.toMillis === "function" ?
              doc.data().recordedAt.toMillis() : null,
          })), members.docs.map((doc) => ({membershipId: doc.id, ...doc.data()}))));
        }
      }
      projected.sort((a, b) => clean(a.businessName).localeCompare(clean(b.businessName)));
      return {accounts: projected};
    });

exports.createBusinessAccount = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const uid = requireAuth(context);
      const db = getFirestore();
      const companyName = clean(data.companyName);
      const businessType = clean(data.businessType);
      const businessEmail = cleanEmail(
          data.businessEmail || context.auth.token.email,
      );
      const businessPhone = clean(data.businessPhone);
      const businessAddress = clean(data.businessAddress);
      const vatNumber = clean(data.vatNumber);
      const businessSize = clean(data.businessSize);
      const termsAccepted = data.acceptTerms === true;
      if (!companyName) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Company name is required.",
        );
      }
      if (!businessEmail || !businessEmail.includes("@")) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Business email is required.",
        );
      }
      if (!businessAddress) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Business address is required.",
        );
      }
      if (!termsAccepted) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Business terms must be accepted.",
        );
      }
      const businessId = `${uid}_${slug(companyName)}`;
      const businessRef = db.collection("businessAccounts").doc(businessId);
      const existingSnap = await businessRef.get();
      if (existingSnap.exists) {
        const existing = existingSnap.data() || {};
        let companyCode = clean(existing.companyCode).replace(/\D/g, "");
        if (!/^\d{8,9}$/.test(companyCode)) {
          companyCode = await reserveCompanyCode(db, businessId, uid);
          await businessRef.set(
              {
                companyCode,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
        }
        return {
          businessId,
          companyCode,
          companyName: existing.businessName || existing.companyName || companyName,
          status: existing.status || "pending",
          approvalStatus: existing.approvalStatus || "pending",
        };
      }
      const companyCode = await reserveCompanyCode(db, businessId, uid);
      const ownerName = clean(context.auth.token.name || businessEmail);
      const batch = db.batch();
      batch.set(businessRef, {
        businessName: companyName,
        companyName,
        businessType,
        contactName: ownerName,
        contactEmail: businessEmail,
        billingEmail: businessEmail,
        phone: businessPhone,
        businessAddress,
        vatNumber,
        businessSize,
        companyCode,
        accountType: "business",
        createdByUserId: uid,
        ownerUid: uid,
        approvalStatus: "pending",
        status: "pending",
        businessStatus: "pending",
        verificationStatus: "pending",
        isApproved: false,
        joinPolicy: "approval_required",
        membershipAuthorityVersion: "business_memberships_v2",
        connectedProducts: ["business", "health+", "gifts", "vanguard"],
        notificationPreferences: {
          deliveryUpdates: true,
          invoices: true,
          teamRequests: true,
        },
        paymentPreferences: {
          defaultMethod: "business_billing",
        },
        permissions: {
          owner: ["*"],
          admin: ["deliveries", "team", "analytics", "settings", "finance"],
          manager: ["deliveries", "team", "analytics", "settings"],
          operations: ["deliveries", "analytics", "history", "healthPlus", "gifts", "vanguard"],
          dispatcher: ["deliveries", "healthPlus", "gifts", "vanguard"],
          finance: ["invoices", "finance", "analytics"],
          viewer: ["analytics", "history"],
          member: ["deliveries"],
        },
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(db.collection("businessWorkspaces").doc(businessId), {
        businessId,
        status: "pending",
        approvalStatus: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(db.collection("businessAnalytics").doc(businessId), {
        businessId,
        deliveryCount: 0,
        monthlySpend: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(db.collection("businessSettings").doc(businessId), {
        businessId,
        joinPolicy: "approval_required",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      batch.set(
          db.collection("business_wallets").doc(businessId),
          {
            businessId,
            balance: 0,
            lifetimeSpent: 0,
            status: "active",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      batch.set(
          db.collection("businessMemberships").doc(`${businessId}_${uid}`),
          {
            businessId,
            userId: uid,
            email: businessEmail,
            name: ownerName,
            role: "owner",
            status: "active",
            permissions: ["owner", "admin"],
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
      );
      batch.set(
          db.collection("users").doc(uid),
          {
            hasBusinessWorkspace: true,
            businessWorkspaceIds: FieldValue.arrayUnion(businessId),
            lastBusinessWorkspaceId: businessId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      await batch.commit();
      return {
        businessId,
        companyCode,
        companyName,
        status: "pending",
        approvalStatus: "pending",
      };
    });

exports.ensureBusinessCompanyCode = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const db = getFirestore();
      const businessId = clean(data.businessId);
      if (!businessId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Business workspace is required.",
        );
      }
      const {uid, ref, account, role} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      if (!new Set(["owner", "admin"]).has(role)) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Business owner or admin access is required.",
        );
      }
      const rotate = data.rotate === true;
      const existingCode = clean(account.companyCode).replace(/\D/g, "");
      if (!rotate && /^\d{8,9}$/.test(existingCode)) {
        await db
            .collection("businessCompanyCodes")
            .doc(existingCode)
            .set(
                {
                  businessId,
                  companyCode: existingCode,
                  ownerUid: account.ownerUid || account.createdByUserId || uid,
                  status: "active",
                  updatedAt: FieldValue.serverTimestamp(),
                },
                {merge: true},
            );
        return {businessId, companyCode: existingCode};
      }

      const codeSnap = await db
          .collection("businessCompanyCodes")
          .where("businessId", "==", businessId)
          .where("status", "==", "active")
          .limit(1)
          .get();
      if (!rotate && !codeSnap.empty) {
        const code = clean(
            codeSnap.docs[0].data().companyCode || codeSnap.docs[0].id,
        ).replace(/\D/g, "");
        if (/^\d{8,9}$/.test(code)) {
          await ref.set(
              {
                companyCode: code,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
          return {businessId, companyCode: code};
        }
      }

      const activeCodes = await db
          .collection("businessCompanyCodes")
          .where("businessId", "==", businessId)
          .where("status", "==", "active")
          .limit(25)
          .get();
      const batch = db.batch();
      activeCodes.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "rotated",
              rotatedAt: FieldValue.serverTimestamp(),
              rotatedBy: uid,
            },
            {merge: true},
        );
      });
      if (/^\d{8,9}$/.test(existingCode)) {
        batch.set(
            db.collection("businessCompanyCodes").doc(existingCode),
            {
              status: "rotated",
              rotatedAt: FieldValue.serverTimestamp(),
              rotatedBy: uid,
            },
            {merge: true},
        );
      }
      const companyCode = await reserveCompanyCode(db, businessId, uid);
      batch.set(
          ref,
          {
            companyCode,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      await batch.commit();
      return {businessId, companyCode};
    });

exports.lookupBusinessByCompanyCode = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      requireAuth(context);
      const code = clean(data.companyCode).replace(/\D/g, "");
      if (!/^\d{8,9}$/.test(code)) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Enter an 8 or 9 digit company code.",
        );
      }
      const db = getFirestore();
      const codeSnap = await db
          .collection("businessCompanyCodes")
          .doc(code)
          .get();
      if (!codeSnap.exists || codeSnap.data().status !== "active") {
        throw new functions.https.HttpsError("not-found", "Company not found.");
      }
      const businessId = codeSnap.data().businessId;
      const businessSnap = await db
          .collection("businessAccounts")
          .doc(businessId)
          .get();
      if (!businessSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Company not found.");
      }
      const business = businessSnap.data();
      return {
        businessId,
        companyName: business.businessName || "Business",
        businessLogo: business.logoUrl || "",
        businessAddress: business.businessAddress || "",
        businessStatus: business.status || "pending",
        joinPolicy: business.joinPolicy || "approval_required",
        roleRequested: "member",
      };
    });

exports.requestBusinessAccess = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const uid = requireAuth(context);
      const db = getFirestore();
      const businessId = clean(data.businessId);
      const role = BUSINESS_ROLES.has(clean(data.role || "member")) ?
      clean(data.role || "member") :
      "member";
      const userEmail = cleanEmail(context.auth.token.email);
      const userName = clean(
          context.auth.token.name || userEmail || "Circum user",
      );
      const businessRef = db.collection("businessAccounts").doc(businessId);
      const businessSnap = await businessRef.get();
      if (!businessSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Company not found.");
      }
      const business = businessSnap.data();
      const existingMembership = await db.collection("businessMemberships").doc(`${businessId}_${uid}`).get();
      if (existingMembership.exists && !["removed", "rejected"].includes(clean(existingMembership.data().status))) {
        return {status: "already_member", businessId};
      }
      const joinPolicy = business.joinPolicy || "approval_required";
      if (joinPolicy === "immediate") {
        await db.runTransaction(async (tx) => {
          tx.set(
              db.collection("businessMemberships").doc(`${businessId}_${uid}`),
              {
                businessId,
                userId: uid,
                email: userEmail,
                name: userName,
                role,
                status: "active",
                joinedAt: FieldValue.serverTimestamp(),
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
              },
          );
          tx.set(
              db.collection("users").doc(uid),
              {
                hasBusinessWorkspace: true,
                businessWorkspaceIds: FieldValue.arrayUnion(businessId),
                lastBusinessWorkspaceId: businessId,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
        });
        return {status: "joined", businessId};
      }
      const requestId = `${businessId}_${uid}`;
      await db.collection("businessJoinRequests").doc(requestId).set(
          {
            businessId,
            userId: uid,
            email: userEmail,
            name: userName,
            roleRequested: role,
            status: "pending",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      const managerMemberships = await db.collection("businessMemberships")
          .where("businessId", "==", businessId).where("status", "==", "active").limit(250).get();
      const managerRecipients = [...new Set(managerMemberships.docs
          .map((doc) => doc.data()).filter((member) => BUSINESS_ADMIN_ROLES.has(clean(member.role)))
          .map((member) => clean(member.userId)).filter(Boolean))];
      await Promise.all(managerRecipients.map((recipientId) => communicationEngine.emitNotification({
        recipientId,
        recipientRole: "sender",
        type: "business_access_requested",
        title: "Business access request",
        body: `${userName} requested access to ${business.businessName || "your Business workspace"}.`,
        data: {
          businessId,
          requestId,
          correlationId: `business_access_request:${requestId}:${recipientId}`,
          category: "business",
        },
      })));
      return {status: "pending", businessId};
    });

exports.reviewBusinessAccessRequest = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const uid = requireAuth(context);
      const db = getFirestore();
      const requestId = clean(data.requestId);
      const approved = data.approved === true;
      const requestRef = db.collection("businessJoinRequests").doc(requestId);
      const requestSnap = await requestRef.get();
      if (!requestSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Access request not found.",
        );
      }
      const request = requestSnap.data();
      const businessRef = db
          .collection("businessAccounts")
          .doc(request.businessId);
      const businessSnap = await businessRef.get();
      if (!businessSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Business workspace not found.",
        );
      }
      const business = businessSnap.data();
      const reviewerAuthority = await resolveBusinessAuthority(db, business, request.businessId, {uid, email: cleanEmail(context.auth.token.email)});
      if (!reviewerAuthority.ownerOrAdmin) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Only Business owners or admins can review access requests.",
        );
      }
      const role = BUSINESS_ROLES.has(request.roleRequested) ?
      request.roleRequested :
      "member";
      const batch = db.batch();
      batch.set(
          requestRef,
          {
            status: approved ? "approved" : "rejected",
            reviewedBy: uid,
            reviewedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      if (approved) {
        batch.set(
            db
                .collection("businessMemberships")
                .doc(`${request.businessId}_${request.userId}`),
            {
              businessId: request.businessId,
              userId: request.userId,
              email: request.email || "",
              name: request.name || "",
              role,
              status: "active",
              joinedAt: FieldValue.serverTimestamp(),
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
        batch.set(
            db.collection("users").doc(request.userId),
            {
              hasBusinessWorkspace: true,
              businessWorkspaceIds: FieldValue.arrayUnion(request.businessId),
              lastBusinessWorkspaceId: request.businessId,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      }
      await batch.commit();
      await communicationEngine.emitNotification({
        recipientId: request.userId,
        recipientRole: "sender",
        type: approved ? "business_access_approved" : "business_access_rejected",
        title: approved ? "Business access approved" : "Business access update",
        body: approved ?
          `You can now open ${business.businessName || "Business"}.` :
          `Your request to join ${business.businessName || "Business"} was not approved.`,
        data: {
          businessId: request.businessId,
          requestId,
          status: approved ? "approved" : "rejected",
          correlationId: `business_access_review:${requestId}:${approved ? "approved" : "rejected"}`,
          category: "business",
        },
      });
      return {
        status: approved ? "approved" : "rejected",
        businessId: request.businessId,
      };
    });

exports.listBusinessAccessRequests = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const businessId = clean(data && data.businessId);
      if (!businessId) {
        throw new functions.https.HttpsError("invalid-argument", "Business workspace is required.");
      }
      const db = getFirestore();
      await requireBusinessAction(db, businessId, context, "team.invite");
      const cursor = data && data.cursor || {};
      let query = db.collection("businessJoinRequests")
          .where("businessId", "==", businessId)
          .where("status", "==", "pending")
          .orderBy("createdAt", "desc")
          .orderBy(FieldPath.documentId(), "desc")
          .limit(51);
      if (Number.isFinite(Number(cursor.createdAtMillis)) && clean(cursor.id)) {
        query = query.startAfter(new Date(Number(cursor.createdAtMillis)), clean(cursor.id));
      }
      const snapshot = await query.get();
      const visible = snapshot.docs.slice(0, 50);
      const requests = visible.map((doc) => {
        const request = doc.data() || {};
        return {
          id: doc.id,
          businessId,
          name: clean(request.name, "Applicant"),
          email: cleanEmail(request.email),
          roleRequested: BUSINESS_ROLES.has(clean(request.roleRequested)) ? clean(request.roleRequested) : "member",
          status: "pending",
          createdAtMillis: request.createdAt && typeof request.createdAt.toMillis === "function" ? request.createdAt.toMillis() : null,
        };
      });
      const last = requests[requests.length - 1];
      return {
        requests,
        nextCursor: snapshot.size > 50 && last && last.createdAtMillis ?
          {createdAtMillis: last.createdAtMillis, id: last.id} : null,
      };
    });

exports.updateBusinessProfile = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const businessId = clean(data.businessId);
      const db = getFirestore();
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const patch = {
        businessName: clean(data.businessName || account.businessName),
        businessType: clean(data.businessType || account.businessType),
        contactEmail: cleanEmail(data.contactEmail || account.contactEmail),
        billingEmail: cleanEmail(
            data.billingEmail ||
          data.contactEmail ||
          account.billingEmail ||
          account.contactEmail,
        ),
        phone: clean(data.phone || account.phone),
        businessAddress: clean(data.businessAddress || account.businessAddress),
        vatNumber: clean(data.vatNumber || account.vatNumber),
        website: clean(data.website || account.website),
        brandColor: clean(data.brandColor || account.brandColor),
        joinPolicy: clean(
            data.joinPolicy || account.joinPolicy || "approval_required",
        ),
        notificationPreferences: {
          ...(account.notificationPreferences || {}),
          ...(data.notificationPreferences || {}),
        },
        paymentPreferences: {
          ...(account.paymentPreferences || {}),
          ...(data.paymentPreferences || {}),
        },
        defaultPickupAddresses: Array.isArray(data.defaultPickupAddresses) ?
        data.defaultPickupAddresses.map(clean).filter(Boolean).slice(0, 10) :
        account.defaultPickupAddresses || [],
        updatedAt: FieldValue.serverTimestamp(),
        updatedByUserId: uid,
      };
      if (!patch.businessName) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Company name is required.",
        );
      }
      if (!patch.contactEmail || !patch.contactEmail.includes("@")) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Business email is required.",
        );
      }
      await ref.set(patch, {merge: true});
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        action: "business_profile_updated",
        changedFields: Object.keys(patch).filter(
            (key) => !["updatedAt", "updatedByUserId"].includes(key),
        ),
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "updated", businessId};
    });

exports.inviteBusinessMember = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      requireAuth(context);
      const businessId = clean(data.businessId);
      const email = cleanEmail(data.email);
      const role = clean(data.role || "member");
      if (!email || !email.includes("@")) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Enter a valid email address.",
        );
      }
      if (!BUSINESS_ROLES.has(role) || role === "owner") {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Choose a valid business role.",
        );
      }
      const db = getFirestore();
      const {uid, ref, account, authority} = await requireBusinessAction(
          db,
          businessId,
          context,
          "team.invite",
      );
      if (authority.role === "custom" && role !== "member") {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Custom roles may invite standard members only.",
        );
      }
      const invitedUser = await db.collection("users").where("email", "==", email).limit(1).get();
      const invitedUserId = invitedUser.empty ? null : invitedUser.docs[0].id;
      const invited = {
        businessId,
        userId: invitedUserId,
        email,
        name: clean(data.name),
        role,
        status: "invited",
        invitedAt: new Date(),
        invitedByUserId: uid,
      };
      const membershipId = invitedUserId ? `${businessId}_${invitedUserId}` : `${businessId}_invite_${email}`;
      await db.collection("businessMemberships").doc(membershipId).set({
        ...invited,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      await ref.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        targetEmail: email,
        action: "business_member_invited",
        role,
        previousState: null,
        newState: {role, status: "invited"},
        reason: clean(data.reason) || null,
        createdAt: FieldValue.serverTimestamp(),
      });
      if (!invitedUser.empty) {
        const recipientId = invitedUser.docs[0].id;
        await communicationEngine.emitNotification({
          recipientId,
          recipientRole: "sender",
          type: "business_invitation",
          title: "Business invitation",
          body: `You have been invited to ${account.businessName || "Circum Business"}.`,
          data: {
            businessId,
            correlationId: `business_invitation:${businessId}:${recipientId}`,
            category: "business",
          },
        });
      }
      return {status: "invited", businessId, email, role};
    });

exports.updateBusinessMemberStatus = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      requireAuth(context);
      const businessId = clean(data.businessId);
      const memberUserId = clean(data.memberUserId);
      const nextStatus = clean(data.status);
      if (
        !memberUserId ||
      !["active", "invited", "suspended", "removed"].includes(nextStatus)
      ) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Choose a valid team member and status.",
        );
      }
      const db = getFirestore();
      const {uid, ref} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const membershipRef = db.collection("businessMemberships").doc(`${businessId}_${memberUserId}`);
      const membershipSnap = await membershipRef.get();
      if (!membershipSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      if (clean(membershipSnap.data().role) === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner status cannot be changed here.",
        );
      }
      await membershipRef.set({
        status: nextStatus,
        updatedAt: FieldValue.serverTimestamp(),
        updatedByUserId: uid,
      }, {merge: true});
      await ref.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        targetUserId: memberUserId,
        action: "business_member_status_updated",
        status: nextStatus,
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: nextStatus, businessId, memberUserId};
    });

exports.recordBusinessIrisMoment = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const businessId = clean(data.businessId);
      const moment =
      data.moment && typeof data.moment === "object" ? data.moment : {};
      const requestId = clean(data.requestId);
      if (!requestId || !/^[A-Za-z0-9_-]{16,80}$/.test(requestId)) {
        throw new functions.https.HttpsError("invalid-argument", "A valid request identity is required.");
      }
      const db = getFirestore();
      const {uid, ref} = await requireBusinessAdmin(db, businessId, context);
      const record = {
        ...moment,
        recordedByUserId: uid,
        recordedAt: FieldValue.serverTimestamp(),
      };
      await ref.collection("irisMoments").doc(requestId).create(record).catch((error) => {
        if (error && (error.code === 6 || error.code === "already-exists")) return;
        throw error;
      });
      await ref.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        action: "business_iris_moment_recorded",
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "recorded", businessId};
    });

exports.updateBusinessMemberRole = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      requireAuth(context);
      const businessId = clean(data.businessId);
      const memberUserId = clean(data.memberUserId);
      const nextRole = clean(data.role);
      if (
        !memberUserId ||
      !BUSINESS_ROLES.has(nextRole) ||
      nextRole === "owner"
      ) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Choose a valid team member and role.",
        );
      }
      const db = getFirestore();
      const {uid, ref} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const membershipRef = db.collection("businessMemberships").doc(`${businessId}_${memberUserId}`);
      const membershipSnap = await membershipRef.get();
      if (!membershipSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      if (clean(membershipSnap.data().role) === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner role cannot be changed here.",
        );
      }
      await membershipRef.set({
        role: nextRole,
        customRoleId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedByUserId: uid,
      }, {merge: true});
      await ref.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        targetUserId: memberUserId,
        action: "business_member_role_updated",
        role: nextRole,
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "updated", businessId, memberUserId, role: nextRole};
    });

exports.removeBusinessMember = functions.runWith({enforceAppCheck: true})
    .region("us-central1")
    .https.onCall(async (data, context) => {
      requireAuth(context);
      const businessId = clean(data.businessId);
      const memberUserId = clean(data.memberUserId);
      if (!memberUserId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Choose a team member.",
        );
      }
      const db = getFirestore();
      const {uid, ref, authority} = await requireBusinessAction(
          db,
          businessId,
          context,
          "team.remove",
      );
      const membershipRef = db.collection("businessMemberships").doc(`${businessId}_${memberUserId}`);
      const membershipSnap = await membershipRef.get();
      if (!membershipSnap.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      const member = membershipSnap.data() || {};
      if (clean(member.role) === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner cannot be removed.",
        );
      }
      if (authority.role === "custom" &&
          ["owner", "admin", "manager"].includes(clean(member.role))) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Custom roles cannot remove Business administrators.",
        );
      }
      await ref.set({updatedAt: FieldValue.serverTimestamp(), updatedByUserId: uid}, {merge: true});
      await membershipRef.set(
              {
                status: "removed",
                removedAt: FieldValue.serverTimestamp(),
                removedByUserId: uid,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        targetUserId: memberUserId,
        action: "business_member_removed",
        previousState: {role: clean(member.role), status: clean(member.status)},
        newState: {role: clean(member.role), status: "removed"},
        reason: clean(data.reason) || null,
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "removed", businessId, memberUserId};
    });

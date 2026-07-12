/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const BUSINESS_ROLES = new Set(["owner", "admin", "dispatcher", "finance", "member"]);

function requireAuth(context) {
  const uid = context.auth && context.auth.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign in to use Circum Business.");
  }
  return uid;
}

function clean(value, fallback = "") {
  return `${value || fallback}`.trim();
}

function cleanEmail(value) {
  return clean(value).toLowerCase();
}

function numericCode() {
  const length = Math.random() < 0.5 ? 8 : 9;
  let out = "";
  for (let i = 0; i < length; i += 1) out += Math.floor(Math.random() * 10);
  if (out[0] === "0") out = `${Math.floor(Math.random() * 9) + 1}${out.slice(1)}`;
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
  throw new functions.https.HttpsError("resource-exhausted", "A unique company code could not be generated. Try again.");
}

exports.createBusinessAccount = functions.region("us-central1").https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const db = getFirestore();
  const companyName = clean(data.companyName);
  const businessType = clean(data.businessType);
  const businessEmail = cleanEmail(data.businessEmail || context.auth.token.email);
  const businessPhone = clean(data.businessPhone);
  const businessAddress = clean(data.businessAddress);
  const vatNumber = clean(data.vatNumber);
  const businessSize = clean(data.businessSize);
  const termsAccepted = data.acceptTerms === true;
  if (!companyName) {
    throw new functions.https.HttpsError("invalid-argument", "Company name is required.");
  }
  if (!businessEmail || !businessEmail.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Business email is required.");
  }
  if (!businessAddress) {
    throw new functions.https.HttpsError("invalid-argument", "Business address is required.");
  }
  if (!termsAccepted) {
    throw new functions.https.HttpsError("failed-precondition", "Business terms must be accepted.");
  }
  const businessRef = db.collection("businessAccounts").doc();
  const businessId = businessRef.id;
  const companyCode = await reserveCompanyCode(db, businessId, uid);
  const ownerName = clean(context.auth.token.name || businessEmail);
  const now = new Date();
  const ownerMember = {
    userId: uid,
    email: businessEmail,
    name: ownerName,
    role: "owner",
    status: "active",
    joinedAt: now,
  };
  const batch = db.batch();
  batch.set(businessRef, {
    businessName: companyName,
    businessType,
    contactName: ownerName,
    contactEmail: businessEmail,
    billingEmail: businessEmail,
    phone: businessPhone,
    businessAddress,
    vatNumber,
    businessSize,
    companyCode,
    createdByUserId: uid,
    ownerUid: uid,
    status: "approved",
    joinPolicy: "approval_required",
    teamMemberIds: [uid, businessEmail],
    managerIds: [uid, businessEmail],
    teamMembers: [ownerMember],
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
      admin: ["deliveries", "team", "analytics", "settings"],
      dispatcher: ["deliveries", "healthPlus", "gifts", "vanguard"],
      finance: ["invoices", "finance", "analytics"],
      member: ["deliveries"],
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection("businessWorkspaces").doc(businessId), {
    businessId,
    status: "active",
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
  batch.set(db.collection("business_wallets").doc(businessId), {
    businessId,
    balance: 0,
    lifetimeSpent: 0,
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection("businessMemberships").doc(`${businessId}_${uid}`), {
    businessId,
    userId: uid,
    email: businessEmail,
    role: "owner",
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.collection("users").doc(uid), {
    hasBusinessWorkspace: true,
    businessWorkspaceIds: FieldValue.arrayUnion(businessId),
    lastBusinessWorkspaceId: businessId,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  return {businessId, companyCode, companyName};
});

exports.lookupBusinessByCompanyCode = functions.region("us-central1").https.onCall(async (data, context) => {
  requireAuth(context);
  const code = clean(data.companyCode).replace(/\D/g, "");
  if (!/^\d{8,9}$/.test(code)) {
    throw new functions.https.HttpsError("invalid-argument", "Enter an 8 or 9 digit company code.");
  }
  const db = getFirestore();
  const codeSnap = await db.collection("businessCompanyCodes").doc(code).get();
  if (!codeSnap.exists || codeSnap.data().status !== "active") {
    throw new functions.https.HttpsError("not-found", "Company not found.");
  }
  const businessId = codeSnap.data().businessId;
  const businessSnap = await db.collection("businessAccounts").doc(businessId).get();
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

exports.requestBusinessAccess = functions.region("us-central1").https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const db = getFirestore();
  const businessId = clean(data.businessId);
  const role = BUSINESS_ROLES.has(clean(data.role || "member")) ? clean(data.role || "member") : "member";
  const userEmail = cleanEmail(context.auth.token.email);
  const userName = clean(context.auth.token.name || userEmail || "Circum user");
  const businessRef = db.collection("businessAccounts").doc(businessId);
  const businessSnap = await businessRef.get();
  if (!businessSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Company not found.");
  }
  const business = businessSnap.data();
  const existingIds = business.teamMemberIds || [];
  if (existingIds.includes(uid) || (userEmail && existingIds.includes(userEmail))) {
    return {status: "already_member", businessId};
  }
  const joinPolicy = business.joinPolicy || "approval_required";
  if (joinPolicy === "immediate") {
    const member = {
      userId: uid,
      email: userEmail,
      name: userName,
      role,
      status: "active",
      joinedAt: new Date(),
    };
    await db.runTransaction(async (tx) => {
      tx.set(businessRef, {
        teamMemberIds: FieldValue.arrayUnion(uid, ...(userEmail ? [userEmail] : [])),
        teamMembers: FieldValue.arrayUnion(member),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(db.collection("businessMemberships").doc(`${businessId}_${uid}`), {
        businessId,
        userId: uid,
        email: userEmail,
        role,
        status: "active",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(db.collection("users").doc(uid), {
        hasBusinessWorkspace: true,
        businessWorkspaceIds: FieldValue.arrayUnion(businessId),
        lastBusinessWorkspaceId: businessId,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    return {status: "joined", businessId};
  }
  const requestId = `${businessId}_${uid}`;
  await db.collection("businessJoinRequests").doc(requestId).set({
    businessId,
    userId: uid,
    email: userEmail,
    name: userName,
    roleRequested: role,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await db.collection("notifications").add({
    userIds: business.managerIds || [business.ownerUid || business.createdByUserId].filter(Boolean),
    category: "business",
    title: "Business access request",
    body: `${userName} requested access to ${business.businessName || "your Business workspace"}.`,
    destination: {route: "business", businessId},
    readBy: [],
    archivedBy: [],
    createdAt: FieldValue.serverTimestamp(),
  });
  return {status: "pending", businessId};
});

exports.reviewBusinessAccessRequest = functions.region("us-central1").https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  const db = getFirestore();
  const requestId = clean(data.requestId);
  const approved = data.approved === true;
  const requestRef = db.collection("businessJoinRequests").doc(requestId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Access request not found.");
  }
  const request = requestSnap.data();
  const businessRef = db.collection("businessAccounts").doc(request.businessId);
  const businessSnap = await businessRef.get();
  if (!businessSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Business workspace not found.");
  }
  const business = businessSnap.data();
  const managers = business.managerIds || [];
  if (business.createdByUserId !== uid && !managers.includes(uid)) {
    throw new functions.https.HttpsError("permission-denied", "Only Business owners or admins can review access requests.");
  }
  const role = BUSINESS_ROLES.has(request.roleRequested) ? request.roleRequested : "member";
  const member = {
    userId: request.userId,
    email: request.email || "",
    name: request.name || "",
    role,
    status: approved ? "active" : "rejected",
    joinedAt: approved ? new Date() : null,
  };
  const batch = db.batch();
  batch.set(requestRef, {
    status: approved ? "approved" : "rejected",
    reviewedBy: uid,
    reviewedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  if (approved) {
    batch.set(businessRef, {
      teamMemberIds: FieldValue.arrayUnion(request.userId, ...(request.email ? [request.email] : [])),
      teamMembers: FieldValue.arrayUnion(member),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(db.collection("businessMemberships").doc(`${request.businessId}_${request.userId}`), {
      businessId: request.businessId,
      userId: request.userId,
      email: request.email || "",
      role,
      status: "active",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    batch.set(db.collection("users").doc(request.userId), {
      hasBusinessWorkspace: true,
      businessWorkspaceIds: FieldValue.arrayUnion(request.businessId),
      lastBusinessWorkspaceId: request.businessId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  batch.set(db.collection("notifications").doc(), {
    userId: request.userId,
    category: "business",
    title: approved ? "Business access approved" : "Business access update",
    body: approved ? `You can now open ${business.businessName || "Business"}.` : `Your request to join ${business.businessName || "Business"} was not approved.`,
    destination: {route: "business", businessId: request.businessId},
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {status: approved ? "approved" : "rejected", businessId: request.businessId};
});

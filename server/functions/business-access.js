/* eslint-disable max-len, require-jsdoc */
const functions = require("firebase-functions/v1");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const BUSINESS_ROLES = new Set([
  "owner",
  "admin",
  "manager",
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

function cleanAddressData(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowed = [
    "displayAddress",
    "formattedAddress",
    "addressLine1",
    "addressLine2",
    "apartment",
    "unit",
    "buildingNumber",
    "street",
    "city",
    "locality",
    "postcode",
    "country",
    "placeId",
    "provider",
    "resolutionPrecision",
  ];
  const cleaned = {};
  for (const key of allowed) {
    const textValue = clean(value[key]);
    if (textValue) cleaned[key] = textValue;
  }
  const lat = Number(value.latitude || value.lat);
  const lng = Number(value.longitude || value.lng);
  if (Number.isFinite(lat)) cleaned.latitude = lat;
  if (Number.isFinite(lng)) cleaned.longitude = lng;
  if (Number.isFinite(lat)) cleaned.lat = lat;
  if (Number.isFinite(lng)) cleaned.lng = lng;
  return Object.keys(cleaned).length ? cleaned : null;
}

function slug(value, fallback = "business") {
  const normalised = clean(value)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 64);
  return normalised || fallback;
}

function memberRole(account = {}, uid, email) {
  const members = Array.isArray(account.teamMembers) ? account.teamMembers : [];
  const match = members.find(
      (member) =>
        (member.userId === uid ||
        (email && `${member.email || ""}`.toLowerCase() === email)) &&
        member.status !== "removed" &&
        member.status !== "rejected",
  );
  if (match) return clean(match.role || "member");
  if (account.createdByUserId === uid || account.ownerUid === uid) {
    return "owner";
  }
  return "";
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
  const role = memberRole(account, uid, email);
  if (!BUSINESS_ADMIN_ROLES.has(role)) {
    throw new functions.https.HttpsError(
        "permission-denied",
        "Business owner, admin, or manager access is required.",
    );
  }
  return {uid, ref, account, role};
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

exports.createBusinessAccount = functions
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
      const businessAddressData = cleanAddressData(data.businessAddressData);
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
        companyName,
        businessType,
        contactName: ownerName,
        contactEmail: businessEmail,
        billingEmail: businessEmail,
        phone: businessPhone,
        businessAddress,
        ...(businessAddressData ? {businessAddressData} : {}),
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
          admin: ["deliveries", "team", "analytics", "settings", "finance"],
          manager: ["deliveries", "team", "analytics", "settings"],
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

exports.ensureBusinessCompanyCode = functions
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
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const role = memberRole(account, uid, cleanEmail(context.auth.token.email));
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

exports.lookupBusinessByCompanyCode = functions
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

exports.requestBusinessAccess = functions
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
      const existingIds = business.teamMemberIds || [];
      if (
        existingIds.includes(uid) ||
      (userEmail && existingIds.includes(userEmail))
      ) {
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
          tx.set(
              businessRef,
              {
                teamMemberIds: FieldValue.arrayUnion(
                    uid,
                    ...(userEmail ? [userEmail] : []),
                ),
                teamMembers: FieldValue.arrayUnion(member),
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
          );
          tx.set(
              db.collection("businessMemberships").doc(`${businessId}_${uid}`),
              {
                businessId,
                userId: uid,
                email: userEmail,
                role,
                status: "active",
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
      await db.collection("notifications").add({
        userIds:
        business.managerIds ||
        [business.ownerUid || business.createdByUserId].filter(Boolean),
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

exports.reviewBusinessAccessRequest = functions
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
      const managers = business.managerIds || [];
      if (business.createdByUserId !== uid && !managers.includes(uid)) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Only Business owners or admins can review access requests.",
        );
      }
      const role = BUSINESS_ROLES.has(request.roleRequested) ?
      request.roleRequested :
      "member";
      const member = {
        userId: request.userId,
        email: request.email || "",
        name: request.name || "",
        role,
        status: approved ? "active" : "rejected",
        joinedAt: approved ? new Date() : null,
      };
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
            businessRef,
            {
              teamMemberIds: FieldValue.arrayUnion(
                  request.userId,
                  ...(request.email ? [request.email] : []),
              ),
              teamMembers: FieldValue.arrayUnion(member),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
        batch.set(
            db
                .collection("businessMemberships")
                .doc(`${request.businessId}_${request.userId}`),
            {
              businessId: request.businessId,
              userId: request.userId,
              email: request.email || "",
              role,
              status: "active",
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
      batch.set(db.collection("notifications").doc(), {
        userId: request.userId,
        category: "business",
        title: approved ? "Business access approved" : "Business access update",
        body: approved ?
        `You can now open ${business.businessName || "Business"}.` :
        `Your request to join ${business.businessName || "Business"} was not approved.`,
        destination: {route: "business", businessId: request.businessId},
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return {
        status: approved ? "approved" : "rejected",
        businessId: request.businessId,
      };
    });

exports.updateBusinessProfile = functions
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
        businessAddressData:
          cleanAddressData(data.businessAddressData) ||
          account.businessAddressData ||
          null,
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
        defaultPickupAddressData: Array.isArray(data.defaultPickupAddressData) ?
        data.defaultPickupAddressData.map(cleanAddressData).filter(Boolean).slice(0, 10) :
        account.defaultPickupAddressData || [],
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

exports.inviteBusinessMember = functions
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
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const existing = Array.isArray(account.teamMembers) ?
      account.teamMembers :
      [];
      const active = existing.filter(
          (member) =>
            cleanEmail(member.email || member.userId) !== email &&
        clean(member.status) !== "removed",
      );
      const invited = {
        userId: email,
        email,
        name: clean(data.name),
        role,
        status: "invited",
        invitedAt: new Date(),
        invitedByUserId: uid,
      };
      const members = [...active, invited];
      const ids = members.flatMap((member) =>
        [clean(member.userId), cleanEmail(member.email)].filter(Boolean),
      );
      const managers = members
          .filter(
              (member) =>
                BUSINESS_ADMIN_ROLES.has(clean(member.role)) &&
          clean(member.status) !== "removed",
          )
          .flatMap((member) =>
            [clean(member.userId), cleanEmail(member.email)].filter(Boolean),
          );
      await ref.set(
          {
            teamMembers: members,
            teamMemberIds: [...new Set(ids)],
            managerIds: [...new Set(managers)],
            updatedAt: FieldValue.serverTimestamp(),
            updatedByUserId: uid,
          },
          {merge: true},
      );
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        targetEmail: email,
        action: "business_member_invited",
        role,
        createdAt: FieldValue.serverTimestamp(),
      });
      await db
          .collection("notifications")
          .doc()
          .set({
            userId: email,
            category: "business",
            title: "Business invitation",
            body: `You have been invited to ${account.businessName || "Circum Business"}.`,
            destination: {route: "business", businessId},
            read: false,
            createdAt: FieldValue.serverTimestamp(),
          });
      return {status: "invited", businessId, email, role};
    });

exports.updateBusinessMemberStatus = functions
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
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const members = Array.isArray(account.teamMembers) ?
      account.teamMembers :
      [];
      const index = members.findIndex(
          (member) =>
            clean(member.userId) === memberUserId ||
        cleanEmail(member.email) === memberUserId,
      );
      if (index < 0) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      if (members[index].role === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner status cannot be changed here.",
        );
      }
      members[index] = {
        ...members[index],
        status: nextStatus,
        updatedAt: new Date(),
        updatedByUserId: uid,
      };
      const activeIds = members
          .filter((item) => clean(item.status) !== "removed")
          .flatMap((item) =>
            [clean(item.userId), cleanEmail(item.email)].filter(Boolean),
          );
      await ref.set(
          {
            teamMembers: members,
            teamMemberIds: [...new Set(activeIds)],
            updatedAt: FieldValue.serverTimestamp(),
            updatedByUserId: uid,
          },
          {merge: true},
      );
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

exports.recordBusinessIrisMoment = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
      const businessId = clean(data.businessId);
      const moment =
      data.moment && typeof data.moment === "object" ? data.moment : {};
      const db = getFirestore();
      const {uid, ref} = await requireBusinessAdmin(db, businessId, context);
      const record = {
        ...moment,
        recordedByUserId: uid,
        recordedAt: new Date(),
      };
      await ref.set(
          {
            irisMoments: FieldValue.arrayUnion(record),
            updatedAt: FieldValue.serverTimestamp(),
            updatedByUserId: uid,
          },
          {merge: true},
      );
      await db.collection("businessAuditLogs").add({
        businessId,
        actorUserId: uid,
        action: "business_iris_moment_recorded",
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "recorded", businessId};
    });

exports.updateBusinessMemberRole = functions
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
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const members = Array.isArray(account.teamMembers) ?
      account.teamMembers :
      [];
      const index = members.findIndex((member) => member.userId === memberUserId);
      if (index < 0) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      if (members[index].role === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner role cannot be changed here.",
        );
      }
      members[index] = {
        ...members[index],
        role: nextRole,
        updatedAt: new Date(),
      };
      const managerIds = members
          .filter(
              (member) =>
                BUSINESS_ADMIN_ROLES.has(clean(member.role)) &&
          member.status !== "removed",
          )
          .flatMap((member) =>
            [member.userId, cleanEmail(member.email)].filter(Boolean),
          );
      await ref.set(
          {
            teamMembers: members,
            managerIds,
            updatedAt: FieldValue.serverTimestamp(),
            updatedByUserId: uid,
          },
          {merge: true},
      );
      await db
          .collection("businessMemberships")
          .doc(`${businessId}_${memberUserId}`)
          .set(
              {
                role: nextRole,
                updatedAt: FieldValue.serverTimestamp(),
                updatedByUserId: uid,
              },
              {merge: true},
          );
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

exports.removeBusinessMember = functions
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
      const {uid, ref, account} = await requireBusinessAdmin(
          db,
          businessId,
          context,
      );
      const members = Array.isArray(account.teamMembers) ?
      account.teamMembers :
      [];
      const member = members.find((item) => item.userId === memberUserId);
      if (!member) {
        throw new functions.https.HttpsError(
            "not-found",
            "Team member not found.",
        );
      }
      if (member.role === "owner") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Owner cannot be removed.",
        );
      }
      const remaining = members.map((item) =>
      item.userId === memberUserId ?
        {...item, status: "removed", removedAt: new Date()} :
        item,
      );
      const activeIds = remaining
          .filter((item) => item.status !== "removed" && item.status !== "rejected")
          .flatMap((item) => [item.userId, cleanEmail(item.email)].filter(Boolean));
      const managerIds = remaining
          .filter(
              (item) =>
                BUSINESS_ADMIN_ROLES.has(clean(item.role)) &&
          item.status !== "removed",
          )
          .flatMap((item) => [item.userId, cleanEmail(item.email)].filter(Boolean));
      await ref.set(
          {
            teamMembers: remaining,
            teamMemberIds: activeIds,
            managerIds,
            updatedAt: FieldValue.serverTimestamp(),
            updatedByUserId: uid,
          },
          {merge: true},
      );
      await db
          .collection("businessMemberships")
          .doc(`${businessId}_${memberUserId}`)
          .set(
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
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: "removed", businessId, memberUserId};
    });

/* eslint-disable max-len, require-jsdoc */
"use strict";
const {queueRecord, emailQueueId} = require("./email-queue");
function accountClosedEmail({uid, email, accountType}) {
  const subject = "Your Circum account has been closed";
  const body = "As requested, your Circum account has been closed. No further action is needed.";
  const html = `<!doctype html><html lang="en"><body style="margin:0;background:#edf3f5;font-family:Arial,sans-serif;color:#123340"><table role="presentation" width="100%"><tr><td style="padding:24px"><table role="presentation" width="100%" style="max-width:600px;margin:auto;background:white;border-radius:16px"><tr><td style="padding:32px"><img src="https://circum-app-2797c.web.app/assets/assets/images/circum_wordmark.png" width="200" alt="Circum"><p style="font-size:12px;letter-spacing:1px;margin-top:24px">ACCOUNT CONFIRMATION</p><h1 style="font-size:30px;line-height:1.25">Your account has been closed.</h1><p>Hi,</p><p style="line-height:1.6">${body}</p><hr style="border:0;border-top:1px solid #e4eaed;margin:24px 0"><p>Thank you for using Circum.</p><p><strong>The Circum Team</strong></p></td></tr></table></td></tr></table></body></html>`;
  return queueRecord({id: emailQueueId(["account_closed", uid]), to: email, subject,
    textBody: `Hi,\n\n${body}\n\nThank you for using Circum.\n\nThe Circum Team`, htmlBody: html,
    eventType: "account_closed", sourceCollection: "closedAccounts", sourceDocumentId: uid,
    sourceRequiredStatus: "ready_for_auth_deletion", senderCategory: "info", recipientRole: accountType,
    extra: {recipientId: uid, templateId: "circum-account-closed", maxAttempts: 20,
      designReference: "resend:0fd7961c-225f-4b61-a7ed-30273fe63b41"}});
}
async function verifyAccountClosed({db, record, auth}) {
  if (record.sourceCollection !== "closedAccounts" || !record.recipientId ||
      record.sourceDocumentId !== record.recipientId) return {status: "suppressed", reason: "closure_metadata_invalid"};
  const snapshot = await db.collection("closedAccounts").doc(record.recipientId).get();
  const closure = snapshot.exists ? snapshot.data() || {} : {};
  if (!snapshot.exists || closure.uid !== record.recipientId || closure.accountType !== record.recipientRole ||
      !["ready_for_auth_deletion", "closed"].includes(closure.status)) return {status: "suppressed", reason: "closure_not_confirmed"};
  try {
    await auth.getUser(record.recipientId);
    return {status: "not_ready", reason: "account_identity_deletion_pending"};
  } catch (error) {
    if (error.code !== "auth/user-not-found") return {status: "not_ready", reason: "account_identity_check_unavailable"};
  }
  return {status: "valid", source: closure};
}
module.exports = {accountClosedEmail, verifyAccountClosed};

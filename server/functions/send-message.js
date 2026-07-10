// Legacy callable name retained for existing Sender and Rider clients.
// All validation and message persistence lives in the canonical engine.
module.exports = require("./communication-engine").sendCircumMessage;

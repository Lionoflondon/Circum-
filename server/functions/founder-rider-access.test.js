"use strict";
const test=require("node:test"); const assert=require("node:assert/strict");
const access=require("./founder-rider-access");
test("only intended UID can receive override",()=>{assert.doesNotThrow(()=>access.assertFounderTarget(access.FOUNDER_RIDER_UID));assert.throws(()=>access.assertFounderTarget("other"));});

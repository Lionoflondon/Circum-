"use strict";

const http = require("node:http");

const MAX_BODY_BYTES = 1024 * 1024;

function createBusinessRothServer(callable) {
  if (typeof callable !== "function") throw new TypeError("callable is required");
  return http.createServer((req, res) => {
    // Firebase callable handlers expect the Express request header helpers.
    req.header = (name) => req.headers[String(name).toLowerCase()];
    req.get = req.header;
    res.status = (code) => {
      res.statusCode = code;
      return res;
    };
    res.send = (body) => {
      if (body !== undefined && typeof body === "object" && !Buffer.isBuffer(body)) {
        res.setHeader("content-type", "application/json; charset=utf-8");
        res.end(JSON.stringify(body));
      } else {
        res.end(body);
      }
      return res;
    };
    res.json = res.send;
    res.set = (name, value) => {
      res.setHeader(name, value);
      return res;
    };

    if (req.url === "/healthz") {
      return res.status(200).send({status: "ok", service: "business-roth-checkout"});
    }
    if (req.url !== "/" && req.url !== "") return res.status(404).send({error: "not_found"});

    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) req.destroy(new Error("request_too_large"));
      else chunks.push(chunk);
    });
    req.on("end", async () => {
      try {
        req.rawBody = Buffer.concat(chunks);
        req.body = req.rawBody.length ? JSON.parse(req.rawBody.toString("utf8")) : {};
        await callable(req, res);
      } catch (error) {
        if (!res.headersSent) res.status(400).send({error: "invalid_request"});
        else if (!res.writableEnded) res.end();
      }
    });
  });
}

if (require.main === module) {
  const callable = require("./index").createBusinessRothCheckout;
  const port = Number(process.env.PORT || 8080);
  createBusinessRothServer(callable).listen(port, "0.0.0.0");
}

module.exports = {createBusinessRothServer};

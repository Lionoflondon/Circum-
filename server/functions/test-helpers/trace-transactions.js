"use strict";

// Test-only observation. Never changes transaction scheduling or retry policy.
module.exports = function traceTransactions(db) {
  if (!process.env.TRACE_TRANSACTIONS) return db;
  let sequence = 0;
  let active = 0;
  const emit = (event, details) => process.stdout.write(JSON.stringify({
    trace: true, pid: process.pid, time: Date.now(), event, active, ...details,
  }) + "\n");
  return new Proxy(db, {
    get(target, key) {
      if (key !== "runTransaction") {
        const value = target[key];
        return typeof value === "function" ? value.bind(target) : value;
      }
      return async (callback, ...options) => {
        const operation = ++sequence;
        let attempt = 0;
        const observed = new WeakSet();
        active += 1;
        emit("start", {operation});
        try {
          const result = await target.runTransaction(async (transaction) => {
            attempt += 1;
            if (!observed.has(transaction)) {
              observed.add(transaction);
              for (const phase of ["commit", "rollback"]) {
                if (typeof transaction[phase] !== "function") continue;
                const original = transaction[phase].bind(transaction);
                transaction[phase] = async (...args) => {
                  const started = Date.now();
                  emit(phase + "_start", {operation, attempt});
                  try {
                    const result = await original(...args);
                    emit(phase + "_end", {operation, attempt, ms: Date.now() - started});
                    return result;
                  } catch (error) {
                    emit(phase + "_abort", {operation, attempt, ms: Date.now() - started, code: error.code, message: error.message});
                    throw error;
                  }
                };
              }
            }
            emit(attempt === 1 ? "attempt" : "retry", {operation, attempt});
            const proxy = new Proxy(transaction, {
              get(tx, method) {
                const value = tx[method];
                if (["get", "getAll"].includes(method)) {
                  return async (...args) => {
                    const paths = args.map((arg) => arg && arg.path).filter(Boolean);
                    const start = Date.now();
                    emit("read_start", {operation, attempt, method, paths});
                    try {
                      const result = await value.apply(tx, args);
                      emit("read_end", {operation, attempt, method, paths, ms: Date.now() - start});
                      return result;
                    } catch (error) {
                      emit("read_abort", {operation, attempt, method, paths, ms: Date.now() - start, code: error.code, message: error.message});
                      throw error;
                    }
                  };
                }
                if (["set", "create", "update", "delete"].includes(method)) {
                  return (...args) => {
                    emit("write", {operation, attempt, method, path: args[0].path});
                    return value.apply(tx, args);
                  };
                }
                return typeof value === "function" ? value.bind(tx) : value;
              },
            });
            try {
              const result = await callback(proxy);
              emit("callback_end", {operation, attempt});
              return result;
            } catch (error) {
              emit("callback_abort", {operation, attempt, code: error.code, message: error.message});
              throw error;
            }
          }, ...options);
          emit("commit", {operation, attempt});
          return result;
        } catch (error) {
          emit("abort", {operation, attempt, code: error.code, message: error.message});
          throw error;
        } finally {
          active -= 1;
          emit("cleanup", {operation, attempt});
        }
      };
    },
  });
};

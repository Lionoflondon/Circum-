'use strict';
const {spawnSync} = require('node:child_process');
const {timingSafeEqual} = require('node:crypto');

// Never log values, provider stderr, or hashes of secrets.
function provision(name, value, run = spawnSync) {
  if (!['RESEND_API_KEY', 'GIFTS_EMAIL_FROM'].includes(name) || !value) {
    throw new Error('Missing or unsupported runtime secret');
  }
  const call = (args, input) => run('gcloud', args.concat('--project=circum-2797c'),
      {input, encoding: null, maxBuffer: 1024 * 1024});
  const describe = call(['secrets', 'describe', name, '--format=json']);
  if (describe.status !== 0) {
    if (!String(describe.stderr || '').includes('NOT_FOUND')) {
      throw new Error('Secret metadata unavailable; stopping without creating a version');
    }
    if (call(['secrets', 'create', name, '--replication-policy=automatic']).status !== 0) {
      throw new Error('Secret creation failed');
    }
  } else {
    const latest = call(['secrets', 'versions', 'describe', 'latest', '--secret=' + name, '--format=json']);
    if (latest.status !== 0 && !String(latest.stderr || '').includes('NOT_FOUND')) {
      throw new Error('Latest version metadata unavailable; stopping');
    }
    if (latest.status === 0 && JSON.parse(latest.stdout.toString()).state === 'ENABLED') {
      const old = call(['secrets', 'versions', 'access', 'latest', '--secret=' + name]);
      if (old.status !== 0) throw new Error('Secret comparison unavailable; stopping without creating a version');
      const proposed = Buffer.from(value);
      const current = Buffer.from(old.stdout);
      const same = current.length === proposed.length && timingSafeEqual(current, proposed);
      current.fill(0);
      old.stdout.fill(0);
      proposed.fill(0);
      if (same) return 'unchanged';
    }
  }
  if (call(['secrets', 'versions', 'add', name, '--data-file=-'], Buffer.from(value)).status !== 0) {
    throw new Error('Secret version creation failed');
  }
  return 'created';
}
if (require.main === module) {
  try {
    for (const name of ['RESEND_API_KEY', 'GIFTS_EMAIL_FROM']) {
      console.log(name + ': ' + provision(name, process.env[name]));
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
module.exports = {provision};

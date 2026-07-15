#!/usr/bin/env node

process.stderr.write(
  'Rider deployment blocked: build and deploy from the canonical Circum-Rider repository.\n',
);
process.exit(1);

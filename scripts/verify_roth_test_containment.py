#!/usr/bin/env python3
"""Read-only release gate for caps and the exact reviewed held queues."""
import concurrent.futures
import json
import os
import subprocess
import urllib.request
from pathlib import Path

names = json.loads(Path(os.environ['ROTH_CONTAINMENT_BASELINE']).read_text())['heldSubscriptionNames']
assert len(names) == len(set(names)) == 25

def run(args):
    return json.loads(subprocess.check_output(['gcloud', *args, '--project=circum-2797c', '--format=json'], text=True))

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    retry_future = executor.submit(run, ['run', 'services', 'describe', 'circum-notification-retries', '--region=us-central1'])
    subscriptions_future = executor.submit(run, ['pubsub', 'subscriptions', 'list'])
    retry = retry_future.result()
    subscriptions = subscriptions_future.result()
a = retry['metadata']['annotations']
assert a.get('run.googleapis.com/scalingMode') == 'manual' and a.get('run.googleapis.com/manualInstanceCount') == '0'
for field in ['spec', 'status']:
    for item in retry[field]['traffic']:
        if item.get('revisionName') == 'circum-notification-retries-cost579-20261009':
            assert not item.get('percent', 0) and not item.get('tag')
by_name = {item['name']: item for item in subscriptions}
assert all(name in by_name and not by_name[name].get('pushConfig') for name in names)
token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
request = urllib.request.Request('https://billingbudgets.googleapis.com/v1/billingAccounts/01C711-142DFE-24AA37/budgets', headers={'Authorization': 'Bearer '+token, 'x-goog-user-project': 'circum-2797c'})
with urllib.request.urlopen(request, timeout=45) as response:
    budgets = json.load(response)
assert not budgets.get('nextPageToken')
for service, units, state in [('services/152E-C115-5142', '6', 'CONFIGURED'), ('services/29E7-DA93-CA13', '5', 'ENFORCED')]:
    matches = [b for b in budgets['budgets'] if service in b.get('budgetFilter', {}).get('services', []) and 'projects/516426305461' in b['budgetFilter']['projects']]
    assert len(matches) == 1
    b = matches[0]
    amount = b['amount']['specifiedAmount']
    assert amount['currencyCode'] == 'GBP' and amount['units'] == units and not amount.get('nanos', 0)
    assert b['spendCap']['outputState'] == state
print(json.dumps({'capsPreserved': True, 'holds': 25, 'retryManualZero': True, 'staged579ZeroTraffic': True}))

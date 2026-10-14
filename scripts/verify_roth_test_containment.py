#!/usr/bin/env python3
"""Read-only release gate for caps and the exact reviewed held queues."""
import concurrent.futures
import json
import os
import subprocess
import urllib.request
from pathlib import Path

def verify_controls(retry, subscriptions, budgets, names, profile):
    assert len(names) == len(set(names)) == 25
    a = retry['metadata']['annotations']
    active = profile == 'authorized-rate10-gbp10'
    assert profile in ['paused-gbp6', 'authorized-rate10-gbp10']
    released = 'projects/circum-2797c/subscriptions/eventarc-us-central1-circum-notification-retries-events-v1-sub-402'
    if active:
        assert a.get('run.googleapis.com/scalingMode') == 'automatic'
        template = retry['spec']['template']
        assert template['metadata']['annotations'].get('autoscaling.knative.dev/maxScale') == '1'
        env = {e['name']: e.get('value') for e in template['spec']['containers'][0]['env']}
        assert env.get('CIRCUM_SOURCE_SHA') == '300a9d1b528cd1894f2d7be820457cf4a7190064'
        assert retry['status']['traffic'] == [{'percent': 100, 'revisionName': 'circum-notification-retries-rate10-300a9d1'}]
    else:
        assert a.get('run.googleapis.com/scalingMode') == 'manual' and a.get('run.googleapis.com/manualInstanceCount') == '0'
    for field in ['spec', 'status']:
        for item in retry[field]['traffic']:
            if item.get('revisionName') == 'circum-notification-retries-cost579-20261009':
                assert not item.get('percent', 0) and not item.get('tag')
    by_name = {item['name']: item for item in subscriptions}
    assert all(name in by_name and not by_name[name].get('pushConfig') for name in names if not (active and name == released))
    if active:
        assert released in names
        assert by_name[released].get('pushConfig') == {'attributes': {'x-goog-version': 'v1'}, 'oidcToken': {'audience': 'https://circum-notification-retries-j2b7cicfwq-uc.a.run.app', 'serviceAccountEmail': 'circum-notification-retries@circum-2797c.iam.gserviceaccount.com'}, 'pushEndpoint': 'https://circum-notification-retries-516426305461.us-central1.run.app/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-processNotificationRetries-us-central1'}
    for service, units, state in [('services/152E-C115-5142', '10' if active else '6', 'CONFIGURED'), ('services/29E7-DA93-CA13', '5', 'ENFORCED')]:
        matches = [b for b in budgets['budgets'] if service in b.get('budgetFilter', {}).get('services', []) and 'projects/516426305461' in b['budgetFilter']['projects']]
        assert len(matches) == 1
        b = matches[0]
        amount = b['amount']['specifiedAmount']
        assert amount['currencyCode'] == 'GBP' and amount['units'] == units and not amount.get('nanos', 0)
        assert b['spendCap']['outputState'] == state
    return {'capsPreserved': True, 'holds': 24 if active else 25, 'retryManualZero': not active, 'authorizedRetryRate10': active, 'staged579ZeroTraffic': True}


def main():
    names = json.loads(Path(os.environ['ROTH_CONTAINMENT_BASELINE']).read_text())['heldSubscriptionNames']
    assert len(names) == len(set(names)) == 25

    def run(args):
        return json.loads(subprocess.check_output(['gcloud', *args, '--project=circum-2797c', '--format=json'], text=True))

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        retry_future = executor.submit(run, ['run', 'services', 'describe', 'circum-notification-retries', '--region=us-central1'])
        subscriptions_future = executor.submit(run, ['pubsub', 'subscriptions', 'list'])
        retry = retry_future.result()
        subscriptions = subscriptions_future.result()
    token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
    request = urllib.request.Request('https://billingbudgets.googleapis.com/v1/billingAccounts/01C711-142DFE-24AA37/budgets', headers={'Authorization': 'Bearer '+token, 'x-goog-user-project': 'circum-2797c'})
    with urllib.request.urlopen(request, timeout=45) as response:
        budgets = json.load(response)
    assert not budgets.get('nextPageToken')
    print(json.dumps(verify_controls(retry, subscriptions, budgets, names, os.environ.get('ROTH_CONTROL_PROFILE', 'paused-gbp6'))))

if __name__ == '__main__':
    main()

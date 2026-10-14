import copy
import importlib.util
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('controls', Path(__file__).with_name('verify_roth_test_containment.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ReleaseControlsTest(unittest.TestCase):
    def setUp(self):
        self.released = 'projects/circum-2797c/subscriptions/eventarc-us-central1-circum-notification-retries-events-v1-sub-402'
        self.names = [self.released] + [f'held-{i}' for i in range(24)]
        self.subs = [{'name': n} for n in self.names]
        self.subs[0]['pushConfig'] = {'oidcToken': {'audience': 'https://circum-notification-retries-j2b7cicfwq-uc.a.run.app', 'serviceAccountEmail': 'circum-notification-retries@circum-2797c.iam.gserviceaccount.com'}, 'pushEndpoint': 'https://circum-notification-retries-516426305461.us-central1.run.app/?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2Fcircum-2797c%2Ftopics%2Ffirebase-schedule-processNotificationRetries-us-central1'}
        self.retry = {'metadata': {'annotations': {'run.googleapis.com/scalingMode': 'automatic'}}, 'spec': {'traffic': [], 'template': {'metadata': {'annotations': {'autoscaling.knative.dev/maxScale': '1'}}, 'spec': {'containers': [{'env': [{'name': 'CIRCUM_SOURCE_SHA', 'value': '300a9d1b528cd1894f2d7be820457cf4a7190064'}]}]}}}, 'status': {'traffic': [{'percent': 100, 'revisionName': 'circum-notification-retries-rate10-300a9d1'}]}}
        self.budgets = {'budgets': [{'budgetFilter': {'services': [service], 'projects': ['projects/516426305461']}, 'amount': {'specifiedAmount': {'currencyCode': 'GBP', 'units': units}}, 'spendCap': {'outputState': state}} for service, units, state in [('services/152E-C115-5142', '10', 'CONFIGURED'), ('services/29E7-DA93-CA13', '5', 'ENFORCED')]]}
    def verify(self, profile='authorized-rate10-gbp10'):
        return module.verify_controls(self.retry, self.subs, self.budgets, self.names, profile)
    def test_authorized_state_passes_and_old_profile_rejects_it(self):
        self.assertEqual(self.verify()['holds'], 24)
        with self.assertRaises(AssertionError): self.verify('paused-gbp6')
        with self.assertRaises(AssertionError): self.verify('arbitrary')
    def test_unrelated_queue_release_and_changed_authentication_fail(self):
        self.subs[1]['pushConfig'] = {'pushEndpoint': 'https://example.invalid'}
        with self.assertRaises(AssertionError): self.verify()
        self.subs[1].pop('pushConfig')
        self.subs[0]['pushConfig']['oidcToken']['serviceAccountEmail'] = 'wrong@example.invalid'
        with self.assertRaises(AssertionError): self.verify()
    def test_cap_or_revision_or_scaling_drift_fail(self):
        original = copy.deepcopy((self.retry, self.budgets))
        for change in ['cap', 'source', 'scale', 'traffic', 'staged']:
            self.retry, self.budgets = copy.deepcopy(original)
            if change == 'cap': self.budgets['budgets'][0]['amount']['specifiedAmount']['units'] = '11'
            if change == 'source': self.retry['spec']['template']['spec']['containers'][0]['env'][0]['value'] = 'unknown'
            if change == 'scale': self.retry['spec']['template']['metadata']['annotations']['autoscaling.knative.dev/maxScale'] = '2'
            if change == 'traffic': self.retry['status']['traffic'][0]['percent'] = 99
            if change == 'staged': self.retry['spec']['traffic'] = [{'revisionName': 'circum-notification-retries-cost579-20261009', 'percent': 1}]
            with self.subTest(change=change), self.assertRaises(AssertionError): self.verify()

if __name__ == '__main__': unittest.main()

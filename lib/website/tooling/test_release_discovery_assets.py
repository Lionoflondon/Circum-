import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
from release_discovery_assets import FILES, verify_manifest, verify_config, release, SITE, asset_bytes

class ReleaseBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.before = {path: 'old' for path in FILES}
        self.before.update({'/main.dart.js': 'compiled-app', '/roth/config.js': 'live-config', '/roth/app.js': 'payment-code'})
        self.replacements = {path: 'new' for path in FILES}
        self.after = {**self.before, **self.replacements}

    def test_html_keeps_existing_seo_metadata(self):
        html=asset_bytes("/gifts/discover/index.html").decode()
        self.assertIn('property="og:title"',html)
        self.assertIn('application/ld+json',html)
        self.assertIn('gift-service-icon',html)

    def test_only_approved_assets_change(self):
        verify_manifest(self.before, self.after, self.replacements)

    def test_payment_or_app_mutation_rejected(self):
        for path in ['/main.dart.js', '/roth/config.js', '/roth/app.js']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                verify_manifest(self.before, {**self.after, path: 'changed'}, self.replacements)

    def test_unexpected_addition_or_deletion_rejected(self):
        for after in [{**self.after, '/extra.js': 'x'}, {k:v for k,v in self.after.items() if k!='/main.dart.js'}]:
            with self.assertRaises(ValueError):
                verify_manifest(self.before, after, self.replacements)

    def test_allowlist_cannot_expand(self):
        with self.assertRaises(ValueError):
            verify_manifest(self.before, self.after, {**self.replacements, '/firebase.json': 'bad'})

    def test_missing_baseline_asset_rejected(self):
        with self.assertRaises(ValueError):
            verify_manifest({}, self.replacements, self.replacements)

    def test_config_exact_including_rewrites_and_headers(self):
        config={'rewrites':[{'source':'/api','run':{'serviceId':'owner'}}], 'headers':[{'source':'/**','headers':[]}]}
        verify_config(config, config)
        with self.assertRaises(ValueError):
            verify_config(config, {**config, 'redirects':[]})

class FakeHosting:
    def __init__(self, mutate=None):
        self.current={'name':SITE+'/releases/old','version':{'name':SITE+'/versions/old'}}
        self.config={'rewrites':[{'source':'/api','run':{'serviceId':'unchanged'}}]}
        self.manifest={p:'old' for p in FILES}
        self.manifest['/roth/app.js']='preserved'
        self.mutate=mutate
        self.published=False
    def latest(self): return self.current
    def files(self,version): return dict(self.manifest)
    def complete(self,op): return {'name':SITE+'/versions/new','status':'CREATED'}
    def request(self,path,method='GET',data=None,raw=False):
        if path.endswith(':clone'): return {}
        if path.endswith(':populateFiles'):
            self.manifest.update(data['files'])
            if self.mutate=='payment': self.manifest['/roth/app.js']='bad'
            if self.mutate=='concurrent': self.current={'name':'another','version':{'name':'another'}}
            return {'uploadRequiredHashes':[]}
        if '/releases?' in path:
            self.published=True
            self.current={'name':SITE+'/releases/new','version':{'name':SITE+'/versions/new'}}
            return self.current
        return {'config':{**self.config,**({'changed':True} if self.mutate=='config' and '/new' in path else {})}}

class ReleaseSequenceTests(unittest.TestCase):
    def test_publishes_only_verified_manifest(self):
        h=FakeHosting()
        with tempfile.TemporaryDirectory() as tmp, patch('release_discovery_assets.asset_bytes',return_value=b'asset'), patch('subprocess.check_output',return_value='a'*40):
            report=release(h,SITE+'/versions/old',Path(tmp))
        self.assertTrue(h.published)
        self.assertEqual(report['untouchedFiles'],1)
    def test_wrong_current_version_stops_before_clone(self):
        h=FakeHosting()
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(ValueError):
            release(h,SITE+'/versions/stale',Path(tmp))
        self.assertFalse(h.published)
    def test_mutation_or_concurrent_release_never_publishes(self):
        for mutation in ['payment','config','concurrent']:
            h=FakeHosting(mutation)
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as tmp, patch('release_discovery_assets.asset_bytes',return_value=b'asset'), patch('subprocess.check_output',return_value='a'*40), self.assertRaises(ValueError):
                release(h,SITE+'/versions/old',Path(tmp))
            self.assertFalse(h.published)

if __name__=='__main__': unittest.main()

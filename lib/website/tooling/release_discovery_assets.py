"""Publish only approved discovery assets over an exact current Hosting version.

No Functions, Cloud Run, IAM, billing, Firebase config or compiled app writes.
Uses Hosting versions.clone(finalize=false), populateFiles, finalize and release.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.parse
import urllib.request

SITE = 'sites/circum-2797c'
API = 'https://firebasehosting.googleapis.com/v1beta1/'
FILES = ('/business/discover/index.html', '/gifts/discover/index.html', '/gifts/discover/style.css')
ROOT = Path(__file__).resolve().parents[3]


def verify_manifest(before, after, replacements):
    if set(replacements) != set(FILES):
        raise ValueError('Only the three approved discovery assets may change')
    expected = dict(before)
    if not set(FILES).issubset(expected):
        raise ValueError('Approved assets absent from current release')
    expected.update(replacements)
    if after != expected:
        raise ValueError('Unexpected added, deleted or changed Hosting file')


def verify_config(before, after):
    if before != after:
        raise ValueError('Hosting configuration changed')


class Hosting:
    def __init__(self):
        self.token = os.environ.get('GOOGLE_OAUTH_ACCESS_TOKEN') or subprocess.check_output(
            ['gcloud', 'auth', 'print-access-token'], text=True).strip()

    def request(self, path, method='GET', data=None, raw=False):
        url = path if path.startswith('https://') else API + path
        if not (url.startswith(API) or url.startswith('https://upload-firebasehosting.googleapis.com/')):
            raise ValueError('Unexpected API host')
        headers = {'Authorization': 'Bearer ' + self.token, 'x-goog-user-project': 'circum-2797c'}
        if data is not None:
            headers['Content-Type'] = 'application/octet-stream' if raw else 'application/json'
            if not raw:
                data = json.dumps(data).encode()
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=45) as response:
            body = response.read()
            return json.loads(body) if body else {}

    def latest(self):
        release = self.request(SITE + '/releases?pageSize=1')['releases'][0]
        if release.get('type') != 'DEPLOY':
            raise ValueError('Latest release is not an active deployment')
        return release

    def files(self, version):
        files, cursor = {}, ''
        while True:
            page = self.request(version + '/files?pageSize=1000' + ('&pageToken=' + urllib.parse.quote(cursor, safe='') if cursor else ''))
            for item in page.get('files', []):
                files[item['path']] = item['hash']
            cursor = page.get('nextPageToken')
            if not cursor:
                return files

    def complete(self, operation):
        for _ in range(120):
            if operation.get('done'):
                if operation.get('error'):
                    raise RuntimeError('Hosting clone failed: ' + json.dumps(operation['error']))
                return operation['response']
            time.sleep(1)
            operation = self.request(operation['name'])
        raise TimeoutError('Clone not complete; no public release made')


def asset_bytes(path):
    source = ROOT / ('web' + path)
    if not path.endswith('.html'):
        return source.read_bytes()
    # Apply the same metadata transform as the established public-site build.
    # This preserves existing canonical, social and structured-data treatment.
    script = "const fs=require('fs');const {metadata,pages}=require('./lib/website/tooling/public_site_seo.cjs');const route=process.argv[1];process.stdout.write(metadata(fs.readFileSync(process.argv[2],'utf8'),route,...pages[route]));"
    return subprocess.check_output(['node', '-e', script, path.removesuffix('index.html'), str(source)], cwd=ROOT)


def release(hosting, expected_version, evidence_dir):
    if not expected_version.startswith(SITE + '/versions/'):
        raise ValueError('Wrong Hosting site')
    current = hosting.latest()
    if current['version']['name'] != expected_version:
        raise ValueError('Current public version changed; review again')
    before = hosting.files(expected_version)
    config = hosting.request(expected_version).get('config', {})
    compressed = {path: gzip.compress(asset_bytes(path), mtime=0) for path in FILES}
    hashes = {path: hashlib.sha256(data).hexdigest() for path, data in compressed.items()}
    verify_manifest(before, {**before, **hashes}, hashes)
    clone = hosting.complete(hosting.request(SITE + '/versions:clone', 'POST', {
        'sourceVersion': expected_version, 'finalize': False}))
    version = clone['name']
    if not version.startswith(SITE + '/versions/') or clone.get('status') != 'CREATED':
        raise ValueError('Unexpected cloned version')
    verify_config(config, hosting.request(version).get('config', {}))
    result = hosting.request(version + ':populateFiles', 'POST', {'files': hashes})
    uploads = {hashes[path]: data for path, data in compressed.items()}
    for content_hash in result.get('uploadRequiredHashes', []):
        if content_hash not in uploads:
            raise ValueError('Unexpected upload requested')
        hosting.request(result['uploadUrl'] + '/' + content_hash, 'POST', uploads[content_hash], raw=True)
    verify_manifest(before, hosting.files(version), hashes)
    verify_config(config, hosting.request(version).get('config', {}))
    hosting.request(version + '?updateMask=status', 'PATCH', {'status': 'FINALIZED'})
    verify_manifest(before, hosting.files(version), hashes)
    verify_config(config, hosting.request(version).get('config', {}))
    if hosting.latest()['name'] != current['name']:
        raise ValueError('Concurrent release detected; refusing to overwrite')
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    receipt = hosting.request(SITE + '/releases?versionName=' + urllib.parse.quote(version, safe=''), 'POST', {
        'message': 'Approved Gifts badge and Business spacing only; source ' + sha})
    if hosting.latest()['version']['name'] != version:
        raise ValueError('Published version not current; inspect releases')
    report = {'sourceSHA': sha, 'previousVersion': expected_version, 'version': version,
              'release': receipt.get('name'), 'changedPaths': list(FILES), 'replacementHashes': hashes,
              'untouchedFiles': len(before) - len(FILES), 'hostingConfigIdentical': True}
    evidence_dir.mkdir(parents=True, exist_ok=True)
    (evidence_dir / 'hosting-release.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    release(Hosting(), args.expected_version, args.evidence_dir)

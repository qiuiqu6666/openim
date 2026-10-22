#!/usr/bin/env python3
"""One-time guarded deployment of the 2026-10-22 candidate; run on server as root."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import time
import urllib.request

work = pathlib.Path('/home/ubuntu/media-upload-fallback-20261022')
app = pathlib.Path('/srv/99chat-production/app')
source = app / 'source/open-im-server'
expected = {
    app / 'bin/openim-api': '560c903d7f78d9786274586f7d23e73c0d1989397cbb4f9eb0792dfb9ca4955a',
    app / 'bin/openim-rpc-third': '6e47f476bf584e2a6095113be81490ed3cc874bcdf5effaba5be5a11e98a4c6e',
    source / 'internal/api/router.go': '1d32f0232b08b807d36bf288b4dd1cdfd78c483802e42f309c0140532155e48e',
    source / 'pkg/common/storage/objectstorage/cos.go': 'd854206fc4cab64a5bc91db7a7322e9fc4153e302981a699eb27153d2e4d556e',
}
new_sources = [
    'internal/api/uploadrelay/relay.go', 'internal/api/uploadrelay/relay_test.go',
    'internal/api/uploadrelay/live_test.go',
    'pkg/common/storage/objectstorage/cos_upload_fallback.go',
    'pkg/common/storage/objectstorage/cos_upload_fallback_test.go',
]
units = ['openimservice-openim-rpc-third-0', 'openimservice-openim-api-0']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def restart():
    for unit in units:
        subprocess.run(['systemctl', 'restart', unit], check=True, timeout=45)

def request(path, data=None):
    req = urllib.request.Request('http://127.0.0.1:10002' + path, data=data,
                                 headers={'operationID': 'upload-fallback-release'})
    with urllib.request.urlopen(req, timeout=4) as response:
        return json.load(response)

for path, digest in expected.items():
    assert sha(path) == digest, 'production baseline changed: ' + str(path)
for name in ['server-final', 'api-build', 'third-build', 'sdk-race', 'mobile-tests', 'live']:
    assert (work / (name + '.exit')).read_text().strip() == '0', name + ' did not pass'
for relative in new_sources:
    assert not (source / relative).exists(), 'new source already exists: ' + relative
assert request('/healthz')['status'] == 'ok'

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = pathlib.Path('/srv/99chat-production/backups') / ('upload-fallback-' + stamp)
backup.mkdir(mode=0o700)
for path in expected:
    dest = backup / path.relative_to(app)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)
config_hashes = {str(p): sha(p) for p in (app / 'config/open-im-server').rglob('*') if p.is_file()}
(backup / 'config-hashes.json').write_text(json.dumps(config_hashes, indent=2))

def rollback():
    for path in expected:
        temp = path.with_name(path.name + '.rollback')
        shutil.copy2(backup / path.relative_to(app), temp)
        temp.replace(path)
    for relative in new_sources:
        (source / relative).unlink(missing_ok=True)
    restart()

rollback_lines = ['#!/bin/bash', 'set -e']
for path in expected:
    rollback_lines += [f"cp -a '{backup / path.relative_to(app)}' '{path}.rollback'", f"mv '{path}.rollback' '{path}'"]
for relative in new_sources:
    rollback_lines += [f"rm -f '{source / relative}'"]
rollback_lines += ['systemctl restart ' + ' '.join(units)]
(backup / 'rollback.sh').write_text('\n'.join(rollback_lines) + '\n')
(backup / 'rollback.sh').chmod(0o700)
try:
    for name in ['openim-api', 'openim-rpc-third']:
        temp = app / 'bin' / (name + '.next')
        shutil.copyfile(work / (name + '.new'), temp)
        temp.chmod(0o755)
        temp.replace(app / 'bin' / name)
    for relative in ['internal/api/router.go', 'pkg/common/storage/objectstorage/cos.go'] + new_sources:
        dest = source / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / 'source' / relative, dest)
    restart()
    ready = False
    for _ in range(20):
        try:
            if request('/healthz').get('status') == 'ok':
                ready = True
                break
        except Exception:
            pass
        time.sleep(0.5)
    assert ready, 'API health check failed'
    denied = request('/object/upload_relay', b'x')
    assert denied.get('errCode', 0) != 0, 'unauthenticated relay was accepted'
    subprocess.run(['systemctl', 'is-active'] + units, check=True)
    assert config_hashes == {str(p): sha(p) for p in (app / 'config/open-im-server').rglob('*') if p.is_file()}, 'configuration drift'
    report = {'backup': str(backup), 'health': 'ok', 'unauthenticated_relay': 'denied',
              'binaries': {name: sha(app / 'bin' / name) for name in ['openim-api', 'openim-rpc-third']}}
    (work / 'deployment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
except BaseException:
    rollback()
    raise

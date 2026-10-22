#!/usr/bin/env python3
"""One-time guarded deployment of the 2026-10-23 candidate; run on server as root."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess
import time
import urllib.request

work = pathlib.Path('/home/ubuntu/media-upload-region-20261023')
app = pathlib.Path('/srv/99chat-production/app')
source = app / 'source/open-im-server'
expected = {
    app / 'bin/openim-api': '5fecafbc83f8c34792720ee361dd98896ebe8a4ff429f70c5c8c8664dd76bdb7',
    source / 'internal/api/third.go': '5af4a39648c5a6df114375b41b66ce6d6ad6fba7145ff73d5053120e16937ffe',
    source / 'go.mod': '886be35943c16de2a5888c08278424c71c8c09538dec6e9a6e7442b5547fdb3d',
    source / 'go.sum': '4abc700120622c330c43e5f6383dfef3d754f2a8b07c3835472f4a8668cc5393',
}
new_sources = ['internal/api/uploadregion/region.go', 'internal/api/uploadregion/region_test.go']
units = ['openimservice-openim-api-0']
database = app / 'config/chat/ip2region_v6.xdb'
assert not database.exists(), 'IPv6 database already exists; review baseline'

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
for name in ['region-tests', 'api-tests', 'build', 'sdk-tests', 'mobile-tests', 'download']:
    assert (work / (name + '.exit')).read_text().strip() == '0', name + ' did not pass'
for relative in new_sources:
    assert not (source / relative).exists(), 'new source already exists: ' + relative
assert request('/healthz')['status'] == 'ok'

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = pathlib.Path('/srv/99chat-production/backups') / ('upload-region-' + stamp)
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
    database.unlink(missing_ok=True)
    restart()

rollback_lines = ['#!/bin/bash', 'set -e']
for path in expected:
    rollback_lines += [f"cp -a '{backup / path.relative_to(app)}' '{path}.rollback'", f"mv '{path}.rollback' '{path}'"]
for relative in new_sources:
    rollback_lines += [f"rm -f '{source / relative}'"]
rollback_lines += [f"rm -f '{database}'"]
rollback_lines += ['systemctl restart ' + ' '.join(units)]
(backup / 'rollback.sh').write_text('\n'.join(rollback_lines) + '\n')
(backup / 'rollback.sh').chmod(0o700)
try:
    for name in ['openim-api']:
        temp = app / 'bin' / (name + '.next')
        shutil.copyfile(work / (name + '.new'), temp)
        temp.chmod(0o755)
        temp.replace(app / 'bin' / name)
    for relative in ['internal/api/third.go', 'go.mod', 'go.sum'] + new_sources:
        dest = source / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / 'source' / relative, dest)
    shutil.copyfile(work / 'ip2region_v6.xdb', database)
    database.chmod(0o644)
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
    live = subprocess.run(['sudo', '-u', 'ubuntu', 'env', 'GOTOOLCHAIN=local',
        'UPLOAD_FALLBACK_LIVE_API=http://127.0.0.1:10002', '/srv/99chat-production/tools/go/bin/go',
        'test', './internal/api/uploadrelay', '-run', 'TestLiveCOSAuthenticatedRelay', '-count=1', '-v'],
        cwd=work / 'source', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (work / 'live-api.log').write_bytes(live.stdout)
    (work / 'live-api.exit').write_text(str(live.returncode))
    assert live.returncode == 0, 'live signing/relay verification failed; see live-api.log'
    report = {'backup' : str(backup), 'health': 'ok', 'unauthenticated_relay': 'denied',
              'binaries': {name: sha(app / 'bin' / name) for name in ['openim-api', 'openim-rpc-third']}}
    (work / 'deployment.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
except BaseException:
    rollback()
    raise

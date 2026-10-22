"""One-time deployment of reviewed disaster candidate; run as root on target."""
import datetime, hashlib, json, pathlib, shutil, subprocess, time, urllib.request

work=pathlib.Path('/home/ubuntu/media-upload-disaster-20261023')
app=pathlib.Path('/srv/99chat-production/app')
source=app/'source/open-im-server'
units=['openimservice-openim-rpc-third-0','openimservice-openim-api-0']
files=['internal/rpc/third/third.go','internal/rpc/third/s3.go',
 'internal/rpc/third/storage_route.go','internal/rpc/third/storage_route_test.go',
 'pkg/common/storage/objectstorage/cos_upload_fallback.go','internal/api/uploadrelay/relay.go',
 'internal/api/uploadregion/region.go','internal/api/uploadrelay/live_test.go',
 'internal/api/uploadrelay/live_api_test.go','internal/api/uploadrelay/live_cleanup_test.go']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def restart():
 for unit in units:subprocess.run(['systemctl','restart',unit],check=True,timeout=45)
def health():
 with urllib.request.urlopen('http://127.0.0.1:10002/healthz',timeout=4) as r:return json.load(r).get('status')=='ok'

assert sha(app/'bin/openim-api')=='968ee4bbd0fc3a579db32493ca4d32a1f0864fe7ae70c81b98c94e774c4eae18'
assert sha(app/'bin/openim-rpc-third')=='c788e330d099a1d555aee85aa348eb1b27fd1ef4c7490e7eb194e1a29cd8d8f7'
for name in ['server-tests','sdk-tests','mobile-tests','api-build','third-build','hk-live']:
 assert (work/(name+'.exit')).read_text().strip()=='0',name
baseline=json.loads((work/'baseline.json').read_text())
for rel,digest in baseline.items():
 p=source/rel
 assert (sha(p) if p.exists() else None)==digest,'source changed: '+rel
assert health()
backup=pathlib.Path('/srv/99chat-production/backups')/('upload-disaster-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
backup.mkdir(mode=0o700)
targets={source/f:work/'source'/f for f in files}
targets.update({app/'bin'/n:work/(n+'.new') for n in ['openim-api','openim-rpc-third']})
existing=[];absent=[]
for dest in targets:
 if dest.exists():
  saved=backup/dest.relative_to(app);saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dest,saved);existing.append(dest)
 else:absent.append(dest)
lines=['#!/bin/bash','set -e']
for p in existing:lines.extend([f"cp -a '{backup/p.relative_to(app)}' '{p}.rollback'",f"mv '{p}.rollback' '{p}'"])
for p in absent:lines.append(f"rm -f '{p}'")
lines.append('systemctl restart '+' '.join(units))
rollback=backup/'rollback.sh';rollback.write_text('\n'.join(lines)+'\n');rollback.chmod(0o700)
config_hashes={str(p):sha(p) for p in (app/'config/open-im-server').rglob('*') if p.is_file()}
try:
 for dest,candidate in targets.items():
  dest.parent.mkdir(parents=True,exist_ok=True);temp=dest.with_name(dest.name+'.next')
  shutil.copyfile(candidate,temp);temp.chmod(0o755 if dest.parent==app/'bin' else 0o644);temp.replace(dest)
 restart()
 ready=False
 for _ in range(20):
  try:
   if health():ready=True;break
  except Exception:pass
  time.sleep(.5)
 assert ready,'health failed'
 for hk in ['0','1']:
  result=subprocess.run(['sudo','-u','ubuntu','env','GOTOOLCHAIN=local',
   'UPLOAD_FALLBACK_LIVE_API=http://127.0.0.1:10002','UPLOAD_FALLBACK_LIVE_HK='+hk,
   '/srv/99chat-production/tools/go/bin/go','test','./internal/api/uploadrelay','-run','^TestLiveCOSAuthenticatedRelay$','-count=1','-v'],
   cwd=work/'source',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
  (work/('live-api-'+hk+'.log')).write_bytes(result.stdout)
  (work/('live-api-'+hk+'.exit')).write_text(str(result.returncode))
  assert result.returncode==0,'live verification failed for bucket '+hk
 assert config_hashes=={str(p):sha(p) for p in (app/'config/open-im-server').rglob('*') if p.is_file()},'config drift'
 subprocess.run(['systemctl','is-active']+units,check=True)
 report={'backup':str(backup),'health':'ok','live_guangzhou':'passed','live_hongkong':'passed including completion, logical access and cleanup',
  'binaries':{n:sha(app/'bin'/n) for n in ['openim-api','openim-rpc-third']}}
 (work/'deployment.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
except BaseException:
 subprocess.run([str(rollback)],check=True,timeout=120)
 raise

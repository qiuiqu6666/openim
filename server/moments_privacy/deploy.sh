#!/bin/bash
set -Eeuo pipefail
r=/home/ubuntu/moments-privacy-release-20261021
p=/srv/99chat-production/rpc-release-20261019
b=/srv/99chat-production/backups/moments-privacy-$(date +%Y%m%d-%H%M%S)
[[ $(sha256sum "$p/bin/chat-owner" | cut -d' ' -f1) = 408b04ff9b64014a3f03b3cdaac0760c67ee791b93ddab728503e312f96ab734 ]]
[[ $(sha256sum "$p/bin/chat-api" | cut -d' ' -f1) = 742f26f307dc13019a0959ef7b73d437fb3b2671bd8991c03835ec057371a007 ]]
mkdir -m 700 "$b"
cp -a "$p/bin/chat-owner" "$p/bin/chat-api" "$b/"
sha256sum "$p/bin/chat-rpc" > "$b/ordinary-rpc.sha256"
find "$p/config" "$p/config-owner" "$p/env" -type f -exec sha256sum {} + > "$b/config.sha256"
printf '%s\n' "$b" > "$r/backup-path.txt"
cat > "$b/rollback.sh" <<EOF
#!/bin/bash
set -e
install -m 755 '$b/chat-owner' '$p/bin/chat-owner.rollback'
mv '$p/bin/chat-owner.rollback' '$p/bin/chat-owner'
install -m 755 '$b/chat-api' '$p/bin/chat-api.rollback'
mv '$p/bin/chat-api.rollback' '$p/bin/chat-api'
systemctl restart 99chat-sec-chat-owner
systemctl restart 99chat-sec-chat-api
EOF
chmod 700 "$b/rollback.sh"
rollback(){ echo 'DEPLOY FAILED: restoring previous binaries'; bash "$b/rollback.sh"; }
trap rollback ERR
probe(){ (set -a; source "$p/env/chat-api.env"; set +a; "$r/check-rpc" "$1"); }
install -m 755 "$r/chat-owner.new" "$p/bin/chat-owner.next"
mv "$p/bin/chat-owner.next" "$p/bin/chat-owner"
systemctl restart 99chat-sec-chat-owner
ready=0
for i in {1..20}; do
 if probe 127.0.0.1:30321 > "$r/owner-probe.log" 2>&1 && grep -q 'GetPresenceVisibility code=Code(1002)' "$r/owner-probe.log"; then ready=1; break; fi
 sleep 1
done
[[ $ready = 1 ]]
install -m 755 "$r/chat-api.new" "$p/bin/chat-api.next"
mv "$p/bin/chat-api.next" "$p/bin/chat-api"
systemctl restart 99chat-sec-chat-api
ready=0
for i in {1..20}; do
 if curl -fsS -m 3 -H 'Content-Type: application/json' -H 'operationID: moments-privacy-release-health' http://127.0.0.1:12008/moments/settings > "$r/api-probe.log" && grep -q 'token is empty' "$r/api-probe.log"; then ready=1; break; fi
 sleep 1
done
[[ $ready = 1 ]]
probe 127.0.0.1:30310 > "$r/bridge-probe.log"
grep -q 'GetPresenceVisibility code=Code(1002)' "$r/bridge-probe.log"
sha256sum -c "$b/config.sha256" > "$r/config-unchanged.log"
sha256sum -c "$b/ordinary-rpc.sha256" > "$r/ordinary-rpc-unchanged.log"
systemctl is-active 99chat-sec-chat-owner 99chat-sec-chat-api 99chat-sec-chat-rpc
sha256sum "$p/bin/chat-owner" "$p/bin/chat-api" > "$r/deployed.sha256"
date -Is > "$r/deployed-at.txt"
trap - ERR
echo "DEPLOYED backup=$b"

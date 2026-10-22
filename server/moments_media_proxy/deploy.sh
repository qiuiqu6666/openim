#!/bin/bash
set -Eeuo pipefail
r=/home/ubuntu/moments-media-proxy-20261022
p=/srv/99chat-production/rpc-release-20261019
src=/srv/99chat-production/app/source/chat/internal/api/chat/moment.go
expected=d45d815eb6dadd8809f61918024b9e6a871b896bafd1a3487a5bd47cfa25694b
[[ $(sha256sum "$p/bin/chat-api" | cut -d' ' -f1) = "$expected" ]]
[[ $(cat "$r/regression.exit") = 0 && $(cat "$r/build.exit") = 0 ]]
cmp "$src" /home/ubuntu/device-login-api-fix-20261021/source/internal/api/chat/moment.go
b=/srv/99chat-production/backups/moments-media-proxy-$(date +%Y%m%d-%H%M%S)
mkdir -m 700 "$b"
cp -a "$p/bin/chat-api" "$b/chat-api"
cp -a "$src" "$b/moment.go"
find "$p/config" "$p/config-owner" "$p/env" -type f -exec sha256sum {} + > "$b/config.sha256"
printf '%s\n' "$b" > "$r/backup-path.txt"
cat > "$b/rollback.sh" <<EOF
#!/bin/bash
set -e
install -m 755 '$b/chat-api' '$p/bin/chat-api.rollback'
mv '$p/bin/chat-api.rollback' '$p/bin/chat-api'
cp -a '$b/moment.go' '$src'
systemctl restart 99chat-sec-chat-api
EOF
chmod 700 "$b/rollback.sh"
trap 'bash "$b/rollback.sh"' ERR
install -m 755 "$r/chat-api.new" "$p/bin/chat-api.next"
mv "$p/bin/chat-api.next" "$p/bin/chat-api"
cp "$r/source/internal/api/chat/moment.go" "$src"
systemctl restart 99chat-sec-chat-api
ready=0
for i in {1..20}; do
 if curl -fsS -m 2 -H 'operationID: moments-proxy-health' http://127.0.0.1:12008/moments/settings > "$r/health.json" && grep -q 'token is empty' "$r/health.json"; then ready=1; break; fi
 sleep 1
done
[[ $ready = 1 ]]
curl -fsS -m 5 -H 'operationID: moments-proxy-auth-health' http://127.0.0.1:12008/moments/media/legacy_moment_media_ca1db8ccf1fc5117b74d90f7433dcdb0/content > "$r/media-auth.json"
grep -q 'token is empty' "$r/media-auth.json"
sha256sum -c "$b/config.sha256" > "$r/config-unchanged.log"
systemctl is-active 99chat-sec-chat-api
sha256sum "$p/bin/chat-api" > "$r/deployed.sha256"
date -Is > "$r/deployed-at.txt"
trap - ERR
echo "DEPLOYED backup=$b"

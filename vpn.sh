#!/bin/bash
#
# vpn.sh — connect a FortiGate IPsec conn (PSK + XAuth + email OTP) and stay
# attached. Container entrypoint; the conn must exist in /etc/ipsec.conf.
#
# Usage: vpn.sh [conn]     (default: milize-vpn)   Ctrl+C disconnects.
#
# Type the emailed OTP within ~60s or FortiGate silently drops it.

set -u

CONN="${1:-milize-vpn}"
OTP_FILE=/etc/ipsec.otp          # the patched xauth plugin polls this path
CHARON_LOG=/var/log/charon.log   # see Dockerfile (no journald in a container)

VIP=""
cleanup() {
  [[ -n "$VIP" ]] && iptables -t nat -D POSTROUTING -s "$VIP/32" -j RETURN 2>/dev/null
  rm -f "$OTP_FILE"; ipsec stop >/dev/null 2>&1; pkill -9 charon 2>/dev/null
}
trap 'echo; cleanup; exit 130' INT TERM

rm -f "$OTP_FILE"; : > "$CHARON_LOG"
ipsec start >/dev/null; sleep 3

echo "→ connecting '$CONN'..."
ipsec up "$CONN" >/dev/null 2>&1 & UP=$!

for _ in $(seq 30); do
  grep -q 'OTP challenge detected' "$CHARON_LOG" && break
  kill -0 "$UP" 2>/dev/null || { echo "✗ failed before OTP:"; tail -n 20 "$CHARON_LOG"; cleanup; exit 1; }
  sleep 1
done
grep -q 'OTP challenge detected' "$CHARON_LOG" || { echo "✗ no OTP challenge"; tail -n 20 "$CHARON_LOG"; cleanup; exit 1; }

read -r -p "OTP code (from email): " TOKEN
printf '%s' "${TOKEN//[[:space:]]/}" > "$OTP_FILE"; chmod 600 "$OTP_FILE"

if wait "$UP"; then
  rm -f "$OTP_FILE"
  # The virtual IP often falls inside a Docker bridge subnet; Docker's MASQUERADE
  # then rewrites the source before the XFRM lookup and traffic leaves unencrypted.
  VIP=$(ipsec status | grep -oE '[0-9.]+/32 ===' | head -1 | cut -d/ -f1)
  [[ -n "$VIP" ]] && iptables -t nat -I POSTROUTING 1 -s "$VIP/32" -j RETURN
  echo "✓ connected. Ctrl+C to disconnect."; ipsec statusall
  while ipsec status 2>/dev/null | grep -q ESTABLISHED; do sleep 5; done
  echo "! tunnel dropped"; ipsec statusall; tail -n 30 "$CHARON_LOG"
else
  echo "✗ failed:"; tail -n 20 "$CHARON_LOG"
fi
cleanup

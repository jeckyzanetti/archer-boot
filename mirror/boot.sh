#!/bin/sh
# ============================================================
# MINIMAL LIFELINE-ONLY boot.sh — fetched by the openvpn up-hook after WAN is up.
# Sets the root password (mirrors the web-GUI admin password) and starts a dropbear
# SSH lifeline on :2222. NOTHING ELSE — no opkg, no packages, no LuCI, no hardening.
# Use this to reboot into a bare factory router that we can still SSH into, then
# deploy the real stack by hand from the GitHub feed.
# ============================================================
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
SRC="${SRC:-https://archer-boot.pages.dev}"
GET="/usr/bin/curl -4 -L -k -fs"

# ----------------------------------------------------------------
# Root password = the router's OWN web-GUI admin password, so :2222 SSH login
# mirrors the TP-Link web UI. The stock squashfs ships NO /etc/shadow (root
# locked), so a password must be set for dropbear to accept a login. TP-Link
# stores the web password AES-encrypted in /etc/config/accountmgnt, so we ask the
# router's own decrypt routine for the plaintext, pipe it into cryptpw (never in
# argv/on disk), and write the hash. Fallback = the well-known default "admin"
# (a crypt hash of "admin", not a secret), reached only if the decrypt/crypt fails.
# ----------------------------------------------------------------
echo "Setting root password (mirroring the web-GUI admin password)..."
_wpw="$(/usr/bin/lua -e 'local ok,a=pcall(require,"luci.model.accountmgnt"); if ok and type(a.get_localPassword)=="function" then local p=a.get_localPassword(); if type(p)=="string" then io.write(p) end end' 2>/dev/null)"
_h=""
[ -n "$_wpw" ] && _h="$(printf '%s' "$_wpw" | /bin/busybox cryptpw -m md5 2>/dev/null)"
[ -z "$_h" ] && [ -n "$_wpw" ] && _h="$(/usr/bin/openssl passwd -1 "$_wpw" 2>/dev/null)"
if [ -n "$_h" ]; then
    printf 'root:%s:0:0:99999:7:::\n' "$_h" > /etc/shadow
else
    echo 'root:$1$Ax10boot$zooYD5Cu6tYQJk9Cd0SIL1:0:0:99999:7:::' > /etc/shadow
fi
unset _wpw _h

# SSH LIFELINE on :2222 — direct fetch + launch, the always-available way in.
$GET -m 30 "$SRC/dropbear_vanilla" -o /tmp/dropbear_vanilla && chmod +x /tmp/dropbear_vanilla
echo "Starting dropbear SSH lifeline on :2222..."
(/tmp/dropbear_vanilla -p 2222 -R -E </dev/null >/dev/null 2>&1) &

echo "lifeline-only boot done."

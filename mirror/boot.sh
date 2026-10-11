#!/bin/sh
# ============================================================
# MINIMAL LIFELINE-ONLY boot.sh — fetched by the openvpn up-hook after WAN is up.
# Sets the root password (mirrors the web-GUI admin password) and starts a dropbear
# SSH lifeline on :2222. NOTHING ELSE — no opkg, no packages, no LuCI, no hardening.
# Use this to reboot into a bare factory router that we can still SSH into, then
# deploy the real stack by hand from the GitHub feed.
# ============================================================
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
SRC="${SRC:-https://raw.githubusercontent.com/jeckyzanetti/archer-boot/c847b5c8e9fe7512238767a9f7a345d7fcc00e6a/mirror}"
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

# SSH LIFELINE on :2222 — the first thing to come up, before anything that can fail.
# Fetch is retried: at boot this races the router's WAN/DNS bring-up (observed losing
# that race on 2026-10-11), so 10 rounds x 20s. telnetd is already up (started by the
# caller); this dropbear is the password-SSH lifeline.
n=0
while [ $n -lt 10 ]; do
    $GET -m 30 "$SRC/dropbear_vanilla" -o /tmp/dropbear_vanilla && [ -s /tmp/dropbear_vanilla ] && break
    n=$((n+1)); sleep 20
done
[ -s /tmp/dropbear_vanilla ] || { echo "dropbear fetch failed; no lifeline this boot"; exit 1; }
chmod +x /tmp/dropbear_vanilla
echo "Starting dropbear SSH lifeline on :2222..."
(/tmp/dropbear_vanilla -p 2222 -R -E </dev/null >/dev/null 2>&1) &

# ----------------------------------------------------------------
# STACK BRING-UP (moved here from the flash-config chain so the config stays
# short and all logic lives in this file): fetch install.sh with the same
# retry, unpack /tmp/opt, then install the ax10 package set. Idempotent —
# every trigger (ddns ip_script, WiFi button, manual) can run this safely.
# ----------------------------------------------------------------
n=0
while [ $n -lt 10 ]; do
    $GET -m 300 "$SRC/install.sh" -o /tmp/i.sh && [ -s /tmp/i.sh ] && break
    n=$((n+1)); sleep 20
done
if [ -s /tmp/i.sh ]; then
    /bin/sh /tmp/i.sh
    if [ -x /tmp/opt/opkg ]; then
        /tmp/opt/opkg update
        /tmp/opt/opkg install ax10-busybox ax10-dropbear ax10-debloat ax10-luci
        /etc/init.d/cron start
    else
        echo "install.sh ran but /tmp/opt/opkg missing; stack incomplete"
    fi
else
    echo "install.sh fetch failed; stack not installed this boot"
fi

echo "boot done (lifeline + stack)."

#!/usr/bin/env bash
set -euo pipefail

# Upload an already signed release; safe to retry without rebuilding or publishing GitHub again.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?Usage: sync_update_mirror.sh vX.Y.Z /absolute/release-directory}"
RELEASE_DIR="${2:?Missing release directory}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$RELEASE_DIR" == /* && -d "$RELEASE_DIR" ]]
MIRROR_HOST="${SCREENOFF_MIRROR_HOST:-root@5.78.223.34}"
MIRROR_KEY="${SCREENOFF_MIRROR_SSH_KEY:-$HOME/Projects/keys/id}"
MIRROR_ROOT="/var/www/screenoff-updates"
MIRROR_URL="https://frameflowtech.com/updates/screenoff"
SSH_OPTIONS=(-i "$MIRROR_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none
    -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15)
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

for asset in ScreenOff.zip ScreenOff.dmg appcast.xml SHA256SUMS; do
    [[ -f "$RELEASE_DIR/$asset" && ! -L "$RELEASE_DIR/$asset" ]]
done

# Verify with the pinned public key; no signing key or Keychain prompt is needed for mirroring.
PUBLIC_KEY="$(awk -F '\"' '/SCREENOFF_UPDATE_PUBLIC_KEY:/ { print $2; exit }' "$ROOT_DIR/project.yml")"
xcrun swiftc "$ROOT_DIR/ScreenOff/Services/UpdateSource.swift" \
    "$ROOT_DIR/Script/verify_update_release.swift" -o "$VERIFY_DIR/verify-release"
"$VERIFY_DIR/verify-release" "$RELEASE_DIR" "$TAG" "$PUBLIC_KEY"

UPLOAD_ID="$TAG.$(uuidgen | tr '[:upper:]' '[:lower:]')"
REMOTE_STAGE="$MIRROR_ROOT/.incoming/$UPLOAD_ID"
ssh "${SSH_OPTIONS[@]}" "$MIRROR_HOST" "mkdir -p '$REMOTE_STAGE'"
trap 'rm -rf "$VERIFY_DIR"; ssh "${SSH_OPTIONS[@]}" "$MIRROR_HOST" "rm -rf '\''$REMOTE_STAGE'\''" >/dev/null 2>&1 || true' EXIT
scp "${SSH_OPTIONS[@]}" "$RELEASE_DIR/ScreenOff.zip" "$RELEASE_DIR/ScreenOff.dmg" \
    "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR/SHA256SUMS" "$MIRROR_HOST:$REMOTE_STAGE/"

# All assets arrive first. A locked, atomic symlink switch publishes the complete release.
ssh "${SSH_OPTIONS[@]}" "$MIRROR_HOST" "python3 - '$TAG' '$UPLOAD_ID'" <<'PY'
import fcntl
import hashlib
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

tag, upload_id = sys.argv[1:]
assert re.fullmatch(r"v\d+\.\d+\.\d+", tag)
assert re.fullmatch(re.escape(tag) + r"\.[a-f0-9-]{36}", upload_id)
root = Path('/var/www/screenoff-updates')
stage = root / '.incoming' / upload_id
names = {'ScreenOff.zip', 'ScreenOff.dmg', 'appcast.xml'}
assert {p.name for p in stage.iterdir()} == names | {'SHA256SUMS'}
assert all(p.is_file() and not p.is_symlink() for p in stage.iterdir())
manifest = {}
for line in (stage / 'SHA256SUMS').read_text().splitlines():
    digest, name = line.split()
    assert name in names and name not in manifest and re.fullmatch(r'[a-f0-9]{64}', digest)
    manifest[name] = digest
assert set(manifest) == names
for name, digest in manifest.items():
    assert hashlib.sha256((stage / name).read_bytes()).hexdigest() == digest, name
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = ET.parse(stage / 'appcast.xml').find('./channel/item')
assert item is not None
assert item.findtext('s:shortVersionString', namespaces=ns) == tag[1:]
build = int(item.findtext('s:version', namespaces=ns))
assert build > 0
enclosure = item.find('enclosure')
assert enclosure.get('url') == f'https://github.com/imetn/ScreenOff/releases/download/{tag}/ScreenOff.zip'
assert int(enclosure.get('length')) == (stage / 'ScreenOff.zip').stat().st_size
assert enclosure.get('{'+ns['s']+'}edSignature')

with (root / '.publish.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    latest = root / 'latest'
    if latest.exists():
        previous = ET.parse(latest / 'appcast.xml').find('./channel/item')
        previous_build = int(previous.findtext('s:version', namespaces=ns))
        assert build >= previous_build, 'Refusing to roll back latest to an older build'
        if build == previous_build:
            assert (latest / 'appcast.xml').read_bytes() == (stage / 'appcast.xml').read_bytes(), 'Same build has different feed'
    destination = root / tag
    if destination.exists():
        for name in names | {'SHA256SUMS'}:
            assert (destination / name).read_bytes() == (stage / name).read_bytes(), 'Immutable release differs: ' + name
    else:
        for asset in stage.iterdir():
            asset.chmod(0o644)
        stage.chmod(0o755)
        os.rename(stage, destination)
    next_link = root / ('.latest-' + upload_id)
    next_link.symlink_to(tag)
    os.replace(next_link, latest)
print(f'Mirror published: {tag}, build {build}')
PY

for asset in ScreenOff.zip ScreenOff.dmg appcast.xml SHA256SUMS; do
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 120 --retry 2 \
        "$MIRROR_URL/$TAG/$asset" -o "$VERIFY_DIR/$asset"
    cmp "$RELEASE_DIR/$asset" "$VERIFY_DIR/$asset"
done
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --max-time 30 "$MIRROR_URL/latest/appcast.xml" -o "$VERIFY_DIR/latest.xml"
cmp "$RELEASE_DIR/appcast.xml" "$VERIFY_DIR/latest.xml"
echo "更新镜像已同步并通过公网逐字节校验：$MIRROR_URL/latest/appcast.xml"

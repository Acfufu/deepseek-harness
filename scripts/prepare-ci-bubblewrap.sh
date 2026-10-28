#!/usr/bin/env bash
set -euo pipefail

# CI needs only the signed-archive payload (a full `apt-get install` scans the
# hosted image's entire dpkg database and runs post-install hooks), extracted
# into the ephemeral runner directory. This used to pin a hand-picked pool URL
# + SHA256, but archive.ubuntu.com garbage-collects superseded point releases —
# the pin 404'd the moment 0.9.0-1ubuntu0.1 was replaced by 0.9.0-1ubuntu0.3
# (2026-09) and the nightly e2e never ran again. So fetch whatever the current
# signed pocket publishes instead: refresh the lists (image ones are baked
# weeks stale), then `apt-get download`, which authenticates the .deb against
# the GPG-signed Release/Packages chain — a stronger check than a manual
# SHA256, with no pin left to rot as security updates land.
: "${RUNNER_TEMP:?prepare-ci-bubblewrap requires RUNNER_TEMP}"
: "${GITHUB_PATH:?prepare-ci-bubblewrap requires GITHUB_PATH}"

if [[ "$(uname -s)" != 'Linux' || "$(uname -m)" != 'x86_64' ]]; then
  echo 'prepare-ci-bubblewrap supports only Linux x86_64 hosted runners' >&2
  exit 1
fi

root="${RUNNER_TEMP}/dsh-bubblewrap"

sudo apt-get update --quiet

(
  cd "$RUNNER_TEMP"
  apt-get download --quiet bubblewrap
)
shopt -s nullglob
archives=("$RUNNER_TEMP"/bubblewrap_*_amd64.deb)
if [[ ${#archives[@]} -ne 1 ]]; then
  echo "expected exactly one downloaded bubblewrap .deb, found ${#archives[@]}" >&2
  exit 1
fi

mkdir -p "$root"
dpkg-deb --extract "${archives[0]}" "$root"
printf '%s\n' "$root/usr/bin" >> "$GITHUB_PATH"

sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 \
  || echo 'apparmor userns knob absent — the functional probe decides'
"$root/usr/bin/bwrap" --version
"$root/usr/bin/bwrap" --ro-bind / / --dev /dev --unshare-pid --proc /proc --die-with-parent -- true
echo 'bubblewrap functional probe passed'

#!/usr/bin/env bash
# Emit one zip + checksum per xcframework and rewrite Package.swift to consume them remotely.
#
# SPM binaryTargets can take `path:` (fine for a checked-out repo) or `url:` + `checksum:`.
# Remote consumers need the latter, and the manifest carrying those URLs has to exist AT the
# release tag -- SPM reads Package.swift from the tag, not from an asset. So this runs during
# a release, after the version is set and before the tag is pushed.
#
# A binaryTarget zip must contain the .xcframework at its ROOT, one per zip; SPM rejects a
# single archive holding several.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:?usage: spm-release.sh <version> <fork-slug> <tag>}"
FORK_SLUG="${2:?}"
TAG="${3:?}"
OUT="${SCRIPT_DIR}/spm-artifacts"

rm -rf "$OUT"; mkdir -p "$OUT"

# Every xcframework a Package.swift binaryTarget references.
# macOS ships bash 3.2, which has no mapfile/readarray.
XCFS=()
while IFS= read -r line; do
  [ -n "$line" ] && XCFS+=("$line")
done < <(
  ls -d "${SCRIPT_DIR}"/frameworkgen/Frameworks/Core/*.xcframework \
        "${SCRIPT_DIR}"/frameworkgen/Frameworks/Sentry/*.xcframework \
        "${SCRIPT_DIR}"/frameworkgen/Frameworks/ReactNative/*.xcframework 2>/dev/null
)
[ "${#XCFS[@]}" -gt 0 ] || { echo "ERROR: no xcframeworks found; run the frameworkgen build first." >&2; exit 1; }

declare -a NAMES=() SUMS=()
for xcf in "${XCFS[@]}"; do
  name="$(basename "$xcf" .xcframework)"
  zip_path="${OUT}/${name}.xcframework.zip"
  # -y keeps symlinks as symlinks; a framework's Versions/Current would otherwise be inflated.
  ( cd "$(dirname "$xcf")" && zip -rqy "$zip_path" "$(basename "$xcf")" )
  sum="$(swift package compute-checksum "$zip_path")"
  NAMES+=("$name"); SUMS+=("$sum")
  printf '    %-32s %s\n' "$name" "${sum:0:16}..."
done

# Rewrite every binaryTarget from path: to url:/checksum:.
python3 - "$SCRIPT_DIR" "$FORK_SLUG" "$TAG" "${NAMES[@]}" -- "${SUMS[@]}" <<'PY'
import re, sys
root, slug, tag = sys.argv[1], sys.argv[2], sys.argv[3]
rest = sys.argv[4:]
sep = rest.index('--')
names, sums = rest[:sep], rest[sep+1:]
checksums = dict(zip(names, sums))

p = f"{root}/Package.swift"
src = open(p).read()

def swap(m):
    name = m.group(1)
    if name not in checksums:
        raise SystemExit(f"ERROR: binaryTarget '{name}' has no built xcframework/checksum.")
    url = f"https://github.com/{slug}/releases/download/{tag}/{name}.xcframework.zip"
    return (f'.binaryTarget(\n            name: "{name}",\n'
            f'            url: "{url}",\n'
            f'            checksum: "{checksums[name]}"\n        )')

out, n = re.subn(r'\.binaryTarget\(name: "([^"]+)", path: "[^"]+"\)', swap, src)
if n == 0:
    raise SystemExit("ERROR: no path-based binaryTargets found -- already rewritten?")
open(p, 'w').write(out)
print(f"    rewrote {n} binaryTarget(s) to {tag}")
PY

echo "    SPM assets in ${OUT} -- upload them to release ${TAG} alongside the pod zip."

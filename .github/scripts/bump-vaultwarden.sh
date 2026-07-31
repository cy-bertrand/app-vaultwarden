#!/usr/bin/env bash
# Bump the pinned Vaultwarden release and the add-on version that ships it.
#
# Usage: .github/scripts/bump-vaultwarden.sh <vaultwarden-version>
#
# Rewrites, in place:
#   vaultwarden/Dockerfile    the vaultwarden/server tag the image is built from
#   vaultwarden/config.yaml   the add-on version Home Assistant sees
#   vaultwarden/CHANGELOG.md  a new entry on top
#   README.md                 the version this fork advertises
#
# The add-on version follows the shape of the upstream bump: a new Vaultwarden
# minor bumps the add-on minor, a new patch bumps the add-on patch.
#
# In GitHub Actions the resolved versions are written to $GITHUB_OUTPUT as
# `current`, `version` and `addon_version`.
set -euo pipefail

new_app="${1:?usage: bump-vaultwarden.sh <vaultwarden-version>}"
new_app="${new_app#v}"

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
dockerfile="${root}/vaultwarden/Dockerfile"
config="${root}/vaultwarden/config.yaml"
changelog="${root}/vaultwarden/CHANGELOG.md"
readme="${root}/README.md"

cur_app="$(sed -n \
    's|^FROM "vaultwarden/server:\(.*\)" AS vaultwarden$|\1|p' "${dockerfile}")"
cur_addon="$(sed -n 's|^version: \(.*\)$|\1|p' "${config}")"

if [[ -z "${cur_app}" || -z "${cur_addon}" ]]; then
    echo "Could not read the current versions; has the layout changed?" >&2
    exit 1
fi

if [[ "${new_app}" == "${cur_app}" ]]; then
    echo "Already on Vaultwarden ${cur_app}; nothing to do."
    exit 0
fi

if [[ "$(printf '%s\n%s\n' "${cur_app}" "${new_app}" | sort -V | tail -n1)" \
    != "${new_app}" ]]; then
    echo "Refusing to downgrade: pinned ${cur_app}, asked for ${new_app}." >&2
    exit 1
fi

IFS=. read -r cur_major cur_minor _ <<<"${cur_app}"
IFS=. read -r new_major new_minor _ <<<"${new_app}"
IFS=. read -r addon_major addon_minor addon_patch <<<"${cur_addon}"

if [[ "${new_major}.${new_minor}" == "${cur_major}.${cur_minor}" ]]; then
    new_addon="${addon_major}.${addon_minor}.$((addon_patch + 1))"
else
    new_addon="${addon_major}.$((addon_minor + 1)).0"
fi

sed -i \
    "s|^FROM \"vaultwarden/server:.*\" AS vaultwarden$|FROM \"vaultwarden/server:${new_app}\" AS vaultwarden|" \
    "${dockerfile}"

sed -i "s|^version: .*$|version: ${new_addon}|" "${config}"

# Prepend the entry, keeping the "# Changelog" heading in place.
tmp="$(mktemp)"
{
    printf '# Changelog\n\n## %s\n\n- ⬆️ Update Vaultwarden to %s\n' \
        "${new_addon}" "${new_app}"
    tail -n +2 "${changelog}"
} >"${tmp}"
mv "${tmp}" "${changelog}"

# The README headlines the shipped version in a handful of anchored spots. A
# pattern that stops matching only means the README drifts, so warn, do not
# fail the update over prose.
before="$(cat "${readme}")"
sed -i \
    -e "s|^\(# Vaultwarden add-on for Home Assistant — \)[0-9][0-9.]*\( fork\)$|\1${new_app}\2|" \
    -e "s|\*\*Vaultwarden [0-9][0-9.]*\*\*|**Vaultwarden ${new_app}**|g" \
    -e "s|\(\`vaultwarden/server\` [0-9][0-9.]* → \*\*\)[0-9][0-9.]*\(\*\*\)|\1${new_app}\2|" \
    -e "s|a release with [0-9][0-9.]* or newer|a release with ${new_app} or newer|" \
    "${readme}"
if [[ "${before}" == "$(cat "${readme}")" ]]; then
    echo "Warning: README.md was not touched; check its version references." >&2
fi

echo "Vaultwarden ${cur_app} -> ${new_app} (add-on ${cur_addon} -> ${new_addon})"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "current=${cur_app}"
        echo "version=${new_app}"
        echo "addon_version=${new_addon}"
    } >>"${GITHUB_OUTPUT}"
fi

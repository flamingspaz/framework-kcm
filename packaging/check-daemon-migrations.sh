#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

require() {
    file=$1
    pattern=$2
    description=$3

    if ! grep -Fq -- "$pattern" "$root/$file"; then
        echo "Missing framework-kcmd migration ($description) in $file" >&2
        exit 1
    fi
}

require_regex() {
    file=$1
    pattern=$2
    description=$3

    if ! grep -Eq -- "$pattern" "$root/$file"; then
        echo "Missing framework-kcmd migration ($description) in $file" >&2
        exit 1
    fi
}

require_state_move() {
    file=$1
    old_state=$2
    new_state=$3

    if ! awk -v old="$old_state" -v new="$new_state" \
        '$1 == "if" && $4 == old && $10 == new { found = 1 } END { exit !found }' \
        "$root/$file"; then
        echo "Missing guarded framework-kcmd state migration in $file" >&2
        exit 1
    fi
    if ! awk -v old="$old_state" -v new="$new_state" \
        '$1 == "mv" && $2 == old && $3 == new { found = 1 } END { exit !found }' \
        "$root/$file"; then
        echo "Missing framework-kcmd state directory move in $file" >&2
        exit 1
    fi
}

check_migration() {
    file=$1
    old_state=$2
    new_state=$3
    require_regex "$file" '^[[:space:]]*systemctl disable --now framework-kcmd\.service' 'legacy systemd unit shutdown'
    require_state_move "$file" "$old_state" "$new_state"
}

check_migration packaging/arch/framework-kcm.install '/var/lib/framework-kcmd' '/var/lib/frameworkd'
require_regex packaging/arch/framework-kcm.install 'systemctl is-enabled --quiet framework-kcmd\.service' 'legacy service enablement detection'
require_regex packaging/arch/framework-kcm.install 'systemctl enable --now frameworkd\.service' 'new service enablement restoration'

check_migration packaging/debian/preinst '/var/lib/framework-kcmd' '/var/lib/frameworkd'
require packaging/cpack.cmake 'debian/preinst' 'Debian upgrade script inclusion'

check_migration packaging/fedora/framework-kcm.spec '%{_sharedstatedir}/framework-kcmd' '%{_sharedstatedir}/frameworkd'
check_migration packaging/fedora/framework-kcm-git.spec '%{_sharedstatedir}/framework-kcmd' '%{_sharedstatedir}/frameworkd'
require_regex packaging/fedora/framework-kcm.spec 'systemctl is-enabled --quiet framework-kcmd\.service' 'legacy service enablement detection'
require_regex packaging/fedora/framework-kcm.spec 'systemctl enable --now frameworkd\.service' 'new service enablement restoration'
require_regex packaging/fedora/framework-kcm-git.spec 'systemctl is-enabled --quiet framework-kcmd\.service' 'legacy service enablement detection'
require_regex packaging/fedora/framework-kcm-git.spec 'systemctl enable --now frameworkd\.service' 'new service enablement restoration'

require packaging/nix/package.nix 'framework-kcmd = frameworkd;' 'legacy Nix attribute compatibility'

echo 'Framework daemon rename migrations are present for all supported packages.'

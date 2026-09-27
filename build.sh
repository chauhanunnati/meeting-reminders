#!/usr/bin/env bash
# Compiles the Swift sources into .app bundles under ./build/.
#
#   ./build.sh            # builds both MeetingAirplane.app and MeetingCat.app
#   ./build.sh airplane   # builds only MeetingAirplane.app
#   ./build.sh cat        # builds only MeetingCat.app
set -euo pipefail

cd "$(dirname "$0")"

# Sanity check: we need swiftc.
if ! command -v swiftc >/dev/null 2>&1; then
    echo "✗ swiftc not found." >&2
    echo "  Install Xcode Command Line Tools first:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi

build_variant() {
    local variant="$1" app_name src_dir plist
    case "$variant" in
        airplane) app_name="MeetingAirplane"; src_dir="Sources/Airplane"; plist="Info-Airplane.plist" ;;
        cat)      app_name="MeetingCat";      src_dir="Sources/Cat";      plist="Info-Cat.plist" ;;
        *) echo "✗ unknown variant: $variant (expected airplane|cat)" >&2; exit 1 ;;
    esac

    local app_dir="build/${app_name}.app"
    local exec_dir="${app_dir}/Contents/MacOS"
    local res_dir="${app_dir}/Contents/Resources"

    # Fresh bundle dir (leaves the other variant's bundle alone).
    rm -rf "$app_dir"
    mkdir -p "$exec_dir" "$res_dir"

    # Compile shared sources + this variant's overlay.
    swiftc -O \
        -framework AppKit \
        -framework EventKit \
        -framework QuartzCore \
        -o "${exec_dir}/${app_name}" \
        Sources/Shared/*.swift "${src_dir}"/*.swift

    # Copy art assets into the bundle's Resources directory.
    cp art/banner.png "${res_dir}/"
    if [ "$variant" = "airplane" ]; then
        cp art/plane.png "${res_dir}/"
    else
        cp -R art/cat "${res_dir}/cat"
    fi

    # Info.plist tells macOS this is a real app bundle with calendar usage
    # permission (and gives each variant its own bundle id / prefs / TCC entry).
    cp "$plist" "${app_dir}/Contents/Info.plist"

    # Ad-hoc codesign. Required on Apple Silicon for TCC (calendar permission)
    # to grant reliably to a launchd-launched binary.
    codesign --force --deep --sign - "${app_dir}" >/dev/null 2>&1 || true

    echo "✓ Built ${app_dir}"
}

mkdir -p build
if [ $# -eq 0 ]; then
    build_variant airplane
    build_variant cat
else
    for v in "$@"; do build_variant "$v"; done
fi

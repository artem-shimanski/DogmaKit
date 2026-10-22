#!/bin/sh
# Manages a shared cache of EVE SDE dumps and points a package's .SDE at one of them.
set -eu

BASE_URL=https://developers.eveonline.com/static-data/tranquility
ROOT=${EVE_SDE_CACHE:-$HOME/Library/Caches/EVE-SDE}
REGISTRY=$ROOT/.packages
SELF=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    cat <<USAGE
Usage: Scripts/update-sde.sh [--build N] [--package DIR] [--command VERB] [--check] [-h] [-- ARGS...]

  --build N       SDE build to install (default: latest on the site)
  --package DIR   package whose .SDE is linked (default: this repository)
  --command VERB  SwiftPM command plugin to run afterwards, with ARGS appended;
                  default for this repository: generate-schema, then sde-import
  --check         print requested, cached, linked and latest builds and who links each; change nothing

Cache: \$EVE_SDE_CACHE, default ~/Library/Caches/EVE-SDE; one <build>/ directory per dump.
The previous build is removed after a successful update unless another package still links it.
USAGE
}

build= package=$SELF command= check=0
while [ $# -gt 0 ]; do
    case $1 in
        --build) build=${2:?--build needs a value}; shift 2 ;;
        --package) package=${2:?--package needs a value}; shift 2 ;;
        --command) command=${2:?--command needs a value}; shift 2 ;;
        --check) check=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
package=$(cd "$package" && pwd)

# Build number from a _sde.jsonl, empty if unreadable.
build_of() {
    [ -f "$1/_sde.jsonl" ] || return 0
    sed -n 's/.*"buildNumber"[^0-9]*\([0-9][0-9]*\).*/\1/p' "$1/_sde.jsonl" | head -n 1
}

# Build a package's .SDE symlink points at inside the cache, empty otherwise.
cached_link() {
    [ -L "$1/.SDE" ] || return 0
    t=$(readlink "$1/.SDE")
    case $t in
        "$ROOT"/*/*) ;;
        "$ROOT"/?*) echo "${t#"$ROOT"/}" ;;
    esac
}

# Registered packages (other than $2) whose .SDE links build $1.
users_of() {
    [ -f "$REGISTRY" ] || return 0
    while IFS= read -r p || [ -n "$p" ]; do
        [ -n "$p" ] && [ "$p" != "${2:-}" ] || continue
        [ "$(cached_link "$p")" = "$1" ] && echo "$p"
    done < "$REGISTRY"
    return 0
}

latest=$(curl -fsSL "$BASE_URL/latest.jsonl" 2>/dev/null | grep '"_key": *"sde"' | sed -n 's/.*"buildNumber"[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -n 1) || latest=
if [ -z "$latest" ] && [ -z "$build" ]; then
    echo "cannot read the latest build from $BASE_URL/latest.jsonl" >&2
    exit 1
fi
want=${build:-$latest}
linked=$(build_of "$package/.SDE")

if [ "$check" = 1 ]; then
    echo "requested: $want"
    if [ -f "$ROOT/$want/_sde.jsonl" ]; then echo "cached:    yes ($ROOT/$want)"; else echo "cached:    no"; fi
    echo "linked:    ${linked:-none} ($package/.SDE)"
    echo "latest:    ${latest:-unknown}"
    for d in "$ROOT"/*/; do
        [ -f "${d}_sde.jsonl" ] || continue
        b=$(basename "$d")
        echo "cache $b: $(users_of "$b" | paste -sd, - | sed 's/^$/unused/')"
    done
    exit 0
fi

mkdir -p "$ROOT"

# The build this package is linked to now, if it is a cache symlink.
previous=$(cached_link "$package")

# 1. A real .SDE directory goes into the cache first, if its slot is free.
sde=$package/.SDE
if [ ! -L "$sde" ] && [ -e "$sde" ] && [ -n "$linked" ] && [ ! -e "$ROOT/$linked" ]; then
    mv "$sde" "$ROOT/$linked"
    echo "moved the existing .SDE (build $linked) into the cache: $ROOT/$linked"
fi

# 2. Make sure the build is in the cache.
if [ -f "$ROOT/$want/_sde.jsonl" ]; then
    echo "build $want is cached"
else
    tmp=$(mktemp -d "$ROOT/.tmp.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    echo "downloading build $want"
    curl -fL --progress-bar -o "$tmp/sde.zip" "$BASE_URL/eve-online-static-data-$want-jsonl.zip"
    mkdir "$tmp/unzipped"
    unzip -q "$tmp/sde.zip" -d "$tmp/unzipped"
    marker=$(find "$tmp/unzipped" -name _sde.jsonl | head -n 1)
    [ -n "$marker" ] || { echo "no _sde.jsonl in the archive" >&2; exit 1; }
    dir=$(dirname "$marker")
    got=$(build_of "$dir")
    [ "$got" = "$want" ] || { echo "archive holds build '$got', expected $want" >&2; exit 1; }
    mv "$dir" "$ROOT/$want"
    rm -rf "$tmp"
    trap - EXIT
    echo "cached $ROOT/$want"
fi

# 3. Point <package>/.SDE at it; a real directory still in the way is kept aside.
if [ -L "$sde" ]; then
    rm "$sde"
elif [ -e "$sde" ]; then
    aside=$ROOT/.replaced-$(date +%Y%m%d-%H%M%S)
    mv "$sde" "$aside"
    echo "moved the existing .SDE (build ${linked:-unknown}) aside: $aside"
fi
ln -s "$ROOT/$want" "$sde"
echo "$sde -> $ROOT/$want"
grep -qxF "$package" "$REGISTRY" 2>/dev/null || echo "$package" >> "$REGISTRY"

if [ -n "$latest" ] && [ "$latest" -gt "$want" ]; then
    echo "note: the site has a newer build ($latest) than $want"
fi

# 4. Run the plugin command(s).
swiftpm() {
    xcrun swift package --package-path "$package" --allow-writing-to-package-directory "$@"
}
if [ -n "$command" ]; then
    swiftpm "$command" "$@"
elif [ "$package" = "$SELF" ]; then
    swiftpm generate-schema
    # the importer is compiled against the regenerated schema
    xcrun swift build --package-path "$package" --product DogmaDataImporter
    swiftpm sde-import
fi

# 5. Drop the previous build unless another package still links it.
if [ -n "$previous" ] && [ "$previous" != "$want" ] && [ -d "$ROOT/$previous" ]; then
    keep=$(mktemp "$ROOT/.tmp.XXXXXX")
    while IFS= read -r p || [ -n "$p" ]; do
        [ -n "$p" ] || continue
        if [ "$p" = "$package" ] || [ -n "$(cached_link "$p")" ]; then echo "$p" >> "$keep"; fi
    done < "$REGISTRY"
    mv "$keep" "$REGISTRY"
    used=$(users_of "$previous" "$package" | head -n 1)
    if [ -n "$used" ]; then
        echo "kept build $previous: still linked by $used"
    else
        rm -rf "$ROOT/$previous"
        echo "removed the previous build $previous from the cache"
    fi
fi

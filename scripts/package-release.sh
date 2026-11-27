#!/bin/sh
set -eu

addon=QuestionableEfficiency
addon_dir=$(realpath "$addon")
manifest="$addon.toc"
output=$1
staging=$(mktemp -d "$output/.package.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT

# Normalize manifest metadata and file entries from Windows or Linux checkouts.
awk '
    NR == 1 { sub(/^\357\273\277/, "") }
    { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }
' "$addon_dir/$manifest" > "$staging/manifest"
version=$(awk '
    /^##[[:space:]]*Version[[:space:]]*:/ {
        count++
        sub(/^[^:]*:[[:space:]]*/, "")
        version = $0
    }
    END {
        if (count != 1 || version !~ /^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)*$/) exit 1
        print version
    }
' "$staging/manifest") || {
    printf 'Expected one Version header in %s with three or more dot-separated numeric components.\n' "$manifest" >&2
    exit 1
}

stage_file() {
    entry=$(printf '%s' "$1" | tr '\\' '/')
    case "/$entry/" in
        //*) printf 'Absolute addon file path in manifest: %s\n' "$1" >&2; exit 1 ;;
        */../*) printf 'Parent directory in manifest path: %s\n' "$1" >&2; exit 1 ;;
    esac
    source_file=$(realpath "$addon_dir/$entry" 2>/dev/null) || source_file=''
    case "$source_file" in
        "$addon_dir"/*)
            if [ -f "$source_file" ]; then
                destination="$staging/$addon/$entry"
                mkdir -p -- "$(dirname -- "$destination")"
                cp -- "$source_file" "$destination"
                return
            fi
            ;;
    esac
    printf 'Invalid or missing addon file in manifest: %s\n' "$1" >&2
    exit 1
}

stage_file "$manifest"
while IFS= read -r entry; do
    case "$entry" in
        ''|'#'*) continue ;;
    esac
    stage_file "$entry"
done < "$staging/manifest"
cp -- LICENSE "$staging/$addon/LICENSE"

archive="$addon-$version.zip"
(cd "$staging" && zip -q -r -D "$archive" "$addon")
mv -f -- "$staging/$archive" "$output/$archive"
printf 'Created %s\n' "$archive"

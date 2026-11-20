#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
models_dir="$project_dir/Sources/Articulate/Models"
model_dir="$models_dir/HuPER"
revision=eb0268f46c409c0e65c493d2c4c946c37cea6364
base_url="https://huggingface.co/BarrySong/HuPER-CoreML/resolve/$revision"

mkdir -p "$models_dir"
staging="$(mktemp -d "$project_dir/Sources/Articulate/.huper.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT

digest() {
    local algorithm="$1" file="$2"
    case "$algorithm" in
        lfs) shasum -a 256 "$file" | cut -d ' ' -f 1 ;;
        git) git hash-object --no-filters "$file" ;;
    esac
}

fetch() {
    local algorithm="$1" expected="$2" name="$3"
    local installed="$model_dir/$name" target="$staging/$name"
    if [[ -f "$installed" && "$(digest "$algorithm" "$installed")" == "$expected" ]]; then
        return
    fi

    mkdir -p "$(dirname "$target")"
    curl --fail --silent --show-error --location --retry 2 --max-time 300 \
        --proto '=https' --proto-redir '=https' --output "$target" "$base_url/$name"
    if [[ "$(digest "$algorithm" "$target")" != "$expected" ]]; then
        printf 'Checksum mismatch for %s\n' "$name" >&2
        exit 1
    fi
}

fetch git 44ecbf47fd90e75561ae25c03bb4ea9553bed1c0 vocab.json
fetch git f0b088af88a5fb85bcafa5e04e2e5acbc28e3ba3 added_tokens.json
fetch git 814cf889e90991f8c579734287eb0c2021a96c16 HuPER.mlmodelc/metadata.json
fetch git ac4029e144e8d1a49431af63d5a91f8c445ea694 HuPER.mlmodelc/model.mil
fetch lfs ad8cc76f001b2095457aa9c2e345455ba5cfa47a842f5d8aeae7d35d6e36bbd3 HuPER.mlmodelc/coremldata.bin
fetch lfs 1fe58d60e164d99aa786ef04df176bfd5fe9f52ea486cfc05fb13e5ce106ebed HuPER.mlmodelc/analytics/coremldata.bin
fetch lfs 06f9978fd882875ba5e7c215fb093808a08e6cb0865f8ae0706ad9899cc57672 HuPER.mlmodelc/weights/weight.bin

if [[ -d "$model_dir" ]]; then
    cp -R "$staging/." "$model_dir/"
else
    mv "$staging" "$model_dir"
fi
printf 'HuPER Core ML model verified in %s\n' "$model_dir"

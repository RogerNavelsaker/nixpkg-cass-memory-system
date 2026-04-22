#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
manifest_path="$repo_root/nix/package-manifest.json"
tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require git
require jq
require nix
homepage="$(jq -r '.meta.homepage' "$manifest_path")"
default_branch="$(jq -r '.source.defaultBranch // "main"' "$manifest_path")"

if [[ ! "$homepage" =~ ^https://github\.com/([^/]+)/([^/#]+) ]]; then
  echo "failed to parse GitHub owner/repo from homepage: $homepage" >&2
  exit 1
fi

owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
source_repo="${1:-https://github.com/$owner/$repo.git}"
source_ref="${2:-$default_branch}"
upstream_dir="$tmpdir/upstream"

echo "syncing $source_repo @ $source_ref"
git clone --depth 1 --branch "$source_ref" "$source_repo" "$upstream_dir" >/dev/null 2>&1
rev="$(git -C "$upstream_dir" rev-parse HEAD)"
version="$(jq -r '.version' "$upstream_dir/package.json")"
homepage_value="$(jq -r '.homepage // empty' "$upstream_dir/package.json")"
license="$(jq -r '.license // empty' "$upstream_dir/package.json")"

if [[ -z "$homepage_value" ]]; then
  homepage_value="$homepage"
fi

cp "$upstream_dir/bun.lock" "$repo_root/bun.lock"
src_hash="$(
  nix store prefetch-file --json --unpack "https://github.com/$owner/$repo/archive/${rev}.tar.gz" \
    | jq -r '.hash'
)"

nix run github:nix-community/bun2nix?tag=2.0.8 -- \
  -l "$repo_root/bun.lock" \
  -o "$repo_root/bun.nix"

jq \
  --arg owner "$owner" \
  --arg repo "$repo" \
  --arg version "$version" \
  --arg rev "$rev" \
  --arg hash "$src_hash" \
  --arg branch "$source_ref" \
  --arg homepage "$homepage_value" \
  --arg license "$license" \
  '.source.type = "github"
   | .source.owner = $owner
   | .source.repo = $repo
   | .source.channel = "github-head"
   | .source.defaultBranch = $branch
   | .source.version = $version
   | .source.rev = $rev
   | .source.hash = $hash
   | .package.version = $version
   | .meta.homepage = $homepage
   | if $license != "" then .meta.licenseSpdx = $license else . end' \
  "$manifest_path" > "$manifest_path.tmp"
mv "$manifest_path.tmp" "$manifest_path"

echo "updated:"
echo "  source:   $source_repo"
echo "  ref:      $source_ref"
echo "  rev:      $rev"
echo "  hash:     $src_hash"
echo "  version:  $version"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$ROOT/patches"
THIRD_PARTY="$ROOT/codex-rs/third_party"

mkdir -p "$THIRD_PARTY"

PATCH_BIN="${PATCH_BIN:-}"
if [[ -z "$PATCH_BIN" ]]; then
  if command -v gpatch >/dev/null 2>&1; then
    PATCH_BIN="$(command -v gpatch)"
  elif [[ -x /usr/gnu/bin/gpatch ]]; then
    PATCH_BIN="/usr/gnu/bin/gpatch"
  else
    echo "error: GNU patch (gpatch) is required. Install it (e.g. 'pkg install developer/gnu-patch') or set PATCH_BIN." >&2
    exit 1
  fi
fi

TAR_BIN="${TAR_BIN:-}"
if [[ -z "$TAR_BIN" ]]; then
  if command -v gtar >/dev/null 2>&1; then
    TAR_BIN="$(command -v gtar)"
  elif [[ -x /usr/gnu/bin/tar ]]; then
    TAR_BIN="/usr/gnu/bin/tar"
  else
    TAR_BIN="$(command -v tar)"
  fi
fi

say() {
  printf '\033[1;34m[%s]\033[0m %s\n' "$1" "$2"
}

normalize_crlf() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r$//' "$path"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
path.write_text(text.replace('\r\n', '\n'))
PY
 "$path"
  else
    # Fallback to awk if neither perl nor python3 is available.
    awk '{ sub(/\r$/, ""); print }' "$path" > "${path}.tmp" && mv "${path}.tmp" "$path"
  fi
}

apply_repo_patch() {
  local patch_path="$1"
  if [[ ! -f "$patch_path" ]]; then
    say "SKIP" "Repository patch $(basename "$patch_path") not found"
    return
  fi

  say "PATCH" "Applying $(basename "$patch_path")"
  (
    cd "$ROOT"
    if git apply --check --whitespace=nowarn "$patch_path" 2>/dev/null; then
      git apply --whitespace=nowarn "$patch_path"
    elif git am --apply --keep-cr --quiet "$patch_path" 2>/dev/null; then
      say "INFO" "Applied $(basename "$patch_path") via git am --apply"
    elif git apply --check --reverse --whitespace=nowarn "$patch_path" 2>/dev/null; then
      say "INFO" "Skipping $(basename "$patch_path") (already applied?)"
    else
      say "ERROR" "Failed to apply $(basename "$patch_path")"
      exit 1
    fi
  )
}

download_crate() {
  local name="$1" version="$2" dest="$3"
  rm -rf "$dest"
  mkdir -p "$dest"
  say "DL " "${name}@${version}"
  if ! curl -sSL "https://crates.io/api/v1/crates/${name}/${version}/download" \
    | "$TAR_BIN" -xzf - -C "$dest"
  then
    say "ERROR" "Failed to download ${name}@${version}"
    exit 1
  fi

  local inner="$dest/${name}-${version}"
  if [[ -d "$inner" && -f "$inner/Cargo.toml" ]]; then
    # crates.io tarballs often unpack into crate-name/version; flatten it.
    say "INFO" "Flattening ${name}-${version} directory"
    "$TAR_BIN" -cpf - -C "$inner" . | "$TAR_BIN" -xpf - -C "$dest"
    rm -rf "$inner"
  fi

  if [[ -z "$(ls -A "$dest")" ]]; then
    say "ERROR" "Download of ${name}@${version} produced no files"
    exit 1
  fi
}

apply_crate_patch() {
  local dir="$1" patch_file="$2"

  local new_path top_component
  new_path="$(awk '/^\+\+\+ /{print $2; exit}' "$patch_file")"
  new_path="${new_path#./}"
  top_component="${new_path%%/*}"

  local candidates=("$dir")

  if [[ -n "$top_component" && -d "$dir/$top_component" ]]; then
    candidates+=("$dir/$top_component")
  fi

  for candidate in "${candidates[@]}"; do
    if "$PATCH_BIN" -d "$candidate" -p0 --dry-run -i "$patch_file" >/dev/null 2>&1; then
      "$PATCH_BIN" -d "$candidate" -p0 -i "$patch_file"
      return
    fi

    if "$PATCH_BIN" -d "$candidate" -p1 --dry-run -i "$patch_file" >/dev/null 2>&1; then
      "$PATCH_BIN" -d "$candidate" -p1 -i "$patch_file"
      return
    fi
  done

  say "ERROR" "Failed to apply $(basename "$patch_file") in $dir"
  exit 1
}

# 1) tree-sitter を取得してパッチ適用
TREE_VER="0.25.10"
TREE_DIR="$THIRD_PARTY/tree-sitter-$TREE_VER"
download_crate "tree-sitter" "$TREE_VER" "$TREE_DIR"
say "PATCH" "tree-sitter patch"
apply_crate_patch "$TREE_DIR" "$PATCHES/tree-sitter-0.25.10-p0.patch"

# crossterm を取得して vendoring (features/patch 適用前の生ソース)
CROSSTERM_VER="0.28.1"
CROSSTERM_DIR="$THIRD_PARTY/crossterm"
download_crate "crossterm" "$CROSSTERM_VER" "$CROSSTERM_DIR"
normalize_crlf "$CROSSTERM_DIR/src/event/source/unix/tty.rs"

# codex リポジトリにまとめた Solaris 対応コミットを適用
apply_repo_patch "$PATCHES/2026-03-05-codex-solaris-commits.patch"

# Enable Solaris-specific crossterm adjustments (vendored sources + Cargo features).
apply_repo_patch "$PATCHES/crossterm-vendored-o-nonblock.patch"

# 3) 残り3クレートにパッチを適用しておく (path 依存が Cargo 解決に必要)
declare -A REST=(
  [fs4]="0.13.1"
  [daemonize]="0.5.0"
  [nix]="0.28.0"
)

for name in "${!REST[@]}"; do
  ver="${REST[$name]}"
  dest="$THIRD_PARTY/$name-$ver"
  download_crate "$name" "$ver" "$dest"

  patch_file="$PATCHES/$name-$ver-p0.patch"
  if [[ -f "$patch_file" ]]; then
    say "PATCH" "Applying ${name}@${ver} patch"
    apply_crate_patch "$dest" "$patch_file"
  else
    say "SKIP" "No patch for ${name}@${ver}"
  fi
done

# 2) codex-apply-patch をビルド（tree-sitter が vendored 済みなので通る）
say "BUILD" "codex-apply-patch (release)"
(
  cd "$ROOT/codex-rs"
  cargo build -p codex-apply-patch --release
)

say "DONE" "All vendored crates available at $THIRD_PARTY"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT/CHANGELOG.md}"
APPCAST_FILE="${APPCAST_FILE:-$ROOT/appcast.xml}"
MAX_NOTES="${MAX_NOTES:-15}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_ED_KEY="${SPARKLE_ED_KEY:-}"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-}"
EDITOR_CMD="${EDITOR:-${VISUAL:-vi}}"
GH_REPO="mikker/poof"
SKIP_RELEASE_UPLOAD="${SKIP_RELEASE_UPLOAD:-}"
SKIP_PUSH="${SKIP_PUSH:-}"
SKIP_HOMEBREW_TAP_UPDATE="${SKIP_HOMEBREW_TAP_UPDATE:-}"
HOMEBREW_TAP_LOCAL_REPO="${HOMEBREW_TAP_LOCAL_REPO:-$ROOT/../homebrew-tap}"
HOMEBREW_TAP_REPO="${HOMEBREW_TAP_REPO:-mikker/homebrew-tap}"
HOMEBREW_TAP_PATH="${HOMEBREW_TAP_PATH:-Casks/poof.rb}"
HOMEBREW_TAP_BRANCH="${HOMEBREW_TAP_BRANCH:-}"
HOMEBREW_TAP_TOKEN="${HOMEBREW_TAP_TOKEN:-}"

die() {
  echo "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
}

detect_generate_appcast() {
  if [[ -n "$SPARKLE_GENERATE_APPCAST" ]]; then
    [[ -x "$SPARKLE_GENERATE_APPCAST" ]] || die "SPARKLE_GENERATE_APPCAST is not executable: $SPARKLE_GENERATE_APPCAST"
    echo "$SPARKLE_GENERATE_APPCAST"
    return
  fi

  local candidates=(
    "$ROOT/bin/generate_appcast"
    "/opt/homebrew/bin/generate_appcast"
    "/usr/local/bin/generate_appcast"
    "/Applications/Sparkle.app/Contents/MacOS/generate_appcast"
    "$ROOT/.build/sparkle-tools/${SPARKLE_VERSION}/bin/generate_appcast"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  require_cmd curl
  require_cmd tar

  local tools_root="$ROOT/.build/sparkle-tools/${SPARKLE_VERSION}"
  local archive_path="$ROOT/.build/sparkle-tools/Sparkle-${SPARKLE_VERSION}.tar.xz"
  local download_url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  local tool_path="$tools_root/bin/generate_appcast"

  mkdir -p "$ROOT/.build/sparkle-tools"
  echo "Downloading Sparkle tools ${SPARKLE_VERSION}..."
  curl -fsSL -o "$archive_path" "$download_url"

  rm -rf "$tools_root"
  mkdir -p "$tools_root"
  tar -xf "$archive_path" -C "$tools_root"

  if [[ ! -x "$tool_path" ]]; then
    die "Failed to prepare generate_appcast at $tool_path"
  fi

  echo "$tool_path"
}

ensure_changelog_file() {
  [[ -f "$CHANGELOG_FILE" ]] && return 0
  printf "# Changelog\n\n" > "$CHANGELOG_FILE"
}

prepend_changelog_entry() {
  local heading="$1"
  local notes="$2"
  local temp_file

  temp_file="$(mktemp)"
  {
    printf "%s\n\n" "$heading"
    printf "%s\n\n" "$notes"
    cat "$CHANGELOG_FILE"
  } > "$temp_file"
  mv "$temp_file" "$CHANGELOG_FILE"
}

extract_changelog_section() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section
  ' "$CHANGELOG_FILE"
}

edit_changelog() {
  local file="$1"
  local editor_base="${EDITOR_CMD%% *}"

  if ! command -v "$editor_base" >/dev/null 2>&1; then
    echo "Editor not found: $EDITOR_CMD" >&2
    return 1
  fi

  IFS=" " read -r -a editor_args <<< "$EDITOR_CMD"
  "${editor_args[@]}" "$file"
}

generate_notes() {
  local range="$1"
  local count=0
  local output=""
  local subject=""

  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue

    local lower
    lower="$(printf "%s" "$subject" | tr "[:upper:]" "[:lower:]")"
    case "$lower" in
      chore:*|chore\ *|chore\(*|ci:*|ci\ *|ci\(*|build:*|build\ *|build\(*|test:*|test\ *|test\(*|tests:*|tests\ *|tests\(*|docs:*|docs\ *|docs\(*|doc:*|doc\ *|doc\(*|refactor:*|refactor\ *|refactor\(*|style:*|style\ *|style\(*)
        continue
        ;;
    esac
    if [[ "$lower" == *"[skip changelog]"* ]]; then
      continue
    fi

    output+="- $subject"$'\n'
    count=$((count + 1))
    if [[ "$count" -ge "$MAX_NOTES" ]]; then
      break
    fi
  done < <(git -C "$ROOT" log --no-merges --pretty=format:"%s" "$range")

  if [[ -z "$output" ]]; then
    output="- Maintenance release"$'\n'
  fi

  printf "%s" "$output"
}

render_cask() {
  local version="$1"
  local build="$2"
  local sha="$3"
  local repo="$4"

  cat <<EOF
cask "poof" do
  version "${version},${build}"
  sha256 "${sha}"

  url "https://github.com/${repo}/releases/download/v#{version.csv.first}/Poof-#{version.csv.first}-#{version.csv.second}.zip"
  name "Poof"
  desc "macOS text snippet expander"
  homepage "https://github.com/${repo}"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Poof.app"
end
EOF
}

gh_tap() {
  if [[ -n "$HOMEBREW_TAP_TOKEN" ]]; then
    GH_TOKEN="$HOMEBREW_TAP_TOKEN" gh "$@"
  else
    gh "$@"
  fi
}

update_homebrew_tap() {
  local version="$1"
  local build="$2"
  local sha="$3"
  local repo="$4"
  local cask_content

  cask_content="$(render_cask "$version" "$build" "$sha" "$repo")"

  if [[ -d "$HOMEBREW_TAP_LOCAL_REPO/.git" ]]; then
    local local_path="$HOMEBREW_TAP_LOCAL_REPO/$HOMEBREW_TAP_PATH"
    mkdir -p "$(dirname "$local_path")"
    printf "%s\n" "$cask_content" > "$local_path"
    echo "Updated local Homebrew tap cask: $local_path"
    return 0
  fi

  require_cmd gh

  if [[ -z "$HOMEBREW_TAP_BRANCH" ]]; then
    HOMEBREW_TAP_BRANCH="$(gh_tap api "repos/$HOMEBREW_TAP_REPO" --jq ".default_branch")"
  fi

  local existing_sha=""
  existing_sha="$(
    gh_tap api "repos/$HOMEBREW_TAP_REPO/contents/$HOMEBREW_TAP_PATH" \
      --jq ".sha" 2>/dev/null || true
  )"

  local content_b64
  content_b64="$(printf "%s\n" "$cask_content" | base64 | tr -d '\n')"

  local -a args=(
    api
    -X PUT
    "repos/$HOMEBREW_TAP_REPO/contents/$HOMEBREW_TAP_PATH"
    -f "message=Update poof cask to ${version} (${build})"
    -f "content=$content_b64"
    -f "branch=$HOMEBREW_TAP_BRANCH"
  )
  if [[ -n "$existing_sha" ]]; then
    args+=(-f "sha=$existing_sha")
  fi

  gh_tap "${args[@]}" >/dev/null
  echo "Updated remote Homebrew tap cask: $HOMEBREW_TAP_REPO/$HOMEBREW_TAP_PATH"
}

require_cmd git
require_cmd ruby
require_cmd shasum
"$ROOT/scripts/release-package.sh" "$VERSION"

META_FILE="$ROOT/dist/release.json"
if [[ ! -f "$META_FILE" ]]; then
  die "Missing release metadata: $META_FILE"
fi

VERSION="$(ruby -rjson -e 'm=JSON.parse(File.read(ARGV[0])); puts m.fetch("version")' "$META_FILE")"
BUILD="$(ruby -rjson -e 'm=JSON.parse(File.read(ARGV[0])); puts m.fetch("build")' "$META_FILE")"
ZIP="$(ruby -rjson -e 'm=JSON.parse(File.read(ARGV[0])); puts m.fetch("zip")' "$META_FILE")"
SHA256="$(ruby -rjson -e 'm=JSON.parse(File.read(ARGV[0])); puts m.fetch("sha256")' "$META_FILE")"
TAG="v${VERSION}"

if [[ ! -f "$ZIP" ]]; then
  die "Missing release archive: $ZIP"
fi

LAST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
if [[ -n "$LAST_TAG" ]]; then
  CHANGELOG_RANGE="$LAST_TAG..HEAD"
else
  CHANGELOG_RANGE="HEAD"
fi

NOTES="$(generate_notes "$CHANGELOG_RANGE")"
DATE_STAMP="$(date +%Y-%m-%d)"
CHANGELOG_HEADING="## ${VERSION} (${BUILD}) - ${DATE_STAMP}"

ensure_changelog_file
if ! rg -Fq "$CHANGELOG_HEADING" "$CHANGELOG_FILE"; then
  prepend_changelog_entry "$CHANGELOG_HEADING" "$NOTES"
fi

echo "Opening changelog for review: $CHANGELOG_FILE"
if ! edit_changelog "$CHANGELOG_FILE"; then
  echo "WARNING: failed to launch editor; proceeding with generated notes."
fi

RELEASE_NOTES="$(extract_changelog_section "$CHANGELOG_HEADING")"
if [[ -z "${RELEASE_NOTES//[$' \t\r\n']/}" ]]; then
  RELEASE_NOTES="- Maintenance release"
fi

SPARKLE_GENERATE_APPCAST="$(detect_generate_appcast)"
APPCAST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$APPCAST_TMPDIR"' EXIT
cp "$ZIP" "$APPCAST_TMPDIR/"
if [[ -f "$APPCAST_FILE" ]]; then
  cp "$APPCAST_FILE" "$APPCAST_TMPDIR/appcast.xml"
fi
BASE_NAME="$(basename "$ZIP")"
NOTES_FILE="$APPCAST_TMPDIR/${BASE_NAME%.*}.txt"
printf "%s\n" "$RELEASE_NOTES" > "$NOTES_FILE"

DOWNLOAD_PREFIX="https://github.com/${GH_REPO}/releases/download/${TAG}/"

run_appcast() {
  (
    cd "$APPCAST_TMPDIR"

    local -a cmd=(
      "$SPARKLE_GENERATE_APPCAST"
      --download-url-prefix "$DOWNLOAD_PREFIX"
      -o appcast.xml
    )

    if [[ -n "$SPARKLE_KEYCHAIN_ACCOUNT" ]]; then
      cmd+=(--account "$SPARKLE_KEYCHAIN_ACCOUNT")
    fi

    if [[ -n "$SPARKLE_ED_KEY" ]]; then
      printf "%s\n" "$SPARKLE_ED_KEY" | "${cmd[@]}" --ed-key-file - .
    elif [[ -n "$SPARKLE_ED_KEY_FILE" ]]; then
      "${cmd[@]}" --ed-key-file "$SPARKLE_ED_KEY_FILE" .
    else
      "${cmd[@]}" .
    fi
  )
}

run_appcast
if [[ ! -f "$APPCAST_TMPDIR/appcast.xml" ]]; then
  die "generate_appcast did not produce appcast.xml"
fi
cp "$APPCAST_TMPDIR/appcast.xml" "$APPCAST_FILE"

PBXPROJ="$ROOT/Poof.xcodeproj/project.pbxproj"
if ! git -C "$ROOT" diff --quiet -- "$PBXPROJ" "$CHANGELOG_FILE" "$APPCAST_FILE" 2>/dev/null; then
  git -C "$ROOT" add "$PBXPROJ" "$CHANGELOG_FILE" "$APPCAST_FILE"
  git -C "$ROOT" commit -m "Release ${VERSION} (${BUILD})"
  echo "Committed release metadata for ${VERSION} (${BUILD})."
fi

if ! git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  git -C "$ROOT" tag -a "$TAG" -m "Release ${VERSION} (${BUILD})"
  echo "Tagged release: $TAG"
fi

if [[ -z "$SKIP_PUSH" ]]; then
  git -C "$ROOT" push origin HEAD
  git -C "$ROOT" push origin "$TAG"
fi

if [[ -z "$SKIP_RELEASE_UPLOAD" ]]; then
  require_cmd gh
  NOTES_FILE="$(mktemp)"
  trap 'rm -rf "$APPCAST_TMPDIR" "$NOTES_FILE"' EXIT
  printf "%s\n" "$RELEASE_NOTES" > "$NOTES_FILE"

  if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP#$(basename "$ZIP")" --repo "$GH_REPO" --clobber
    gh release edit "$TAG" --repo "$GH_REPO" --title "Poof ${VERSION}" --notes-file "$NOTES_FILE"
    echo "Updated GitHub release: $TAG"
  else
    gh release create "$TAG" "$ZIP#$(basename "$ZIP")" \
      --repo "$GH_REPO" \
      --title "Poof ${VERSION}" \
      --notes-file "$NOTES_FILE"
    echo "Created GitHub release: $TAG"
  fi
fi

if [[ -z "$SKIP_HOMEBREW_TAP_UPDATE" ]]; then
  update_homebrew_tap "$VERSION" "$BUILD" "$SHA256" "$GH_REPO"
fi

echo "Distribution complete for ${VERSION} (${BUILD})."

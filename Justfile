default := "build"
set dotenv-load := true
arch := `uname -m`

build:
  bin/agent-build build -project Poof.xcodeproj -scheme Poof -destination "platform=macOS,arch={{arch}}" CODE_SIGNING_ALLOWED=NO

build-release:
  bash -lc 'set -euo pipefail; bin/build-release-app'

kill:
  pkill -f "Poof.app/Contents/MacOS/Poof" || true

run: build kill
  ./.build/dd/Build/Products/Debug/Poof.app/Contents/MacOS/Poof

test:
  swift test

clean:
  rm -rf .build

config-dir:
  echo "$HOME/Library/Application Support/Poof"

import-raycast FILE OUTPUT_DIR='':
  bash -lc 'set -euo pipefail; if [ -n "{{OUTPUT_DIR}}" ]; then bin/import-raycast-snippets "{{FILE}}" "{{OUTPUT_DIR}}"; else bin/import-raycast-snippets "{{FILE}}"; fi'

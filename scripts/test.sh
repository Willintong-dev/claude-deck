#!/bin/zsh
set -uo pipefail
ROOT=${0:A:h:h}
LOG=$(mktemp)
for attempt in 1 2 3; do
  swift test --package-path "$ROOT" --scratch-path "$ROOT/.build-tests" "$@" 2>&1 | tee "$LOG"
  STATUS=${pipestatus[1]}
  if [[ $STATUS -eq 0 ]] || ! grep -q "plugin for module 'TestingMacros' not found" "$LOG"; then
    break
  fi
  echo "reintentando ($attempt): el plugin de Swift Testing no cargó (falla intermitente sin Xcode)"
  rm -rf "$ROOT/.build-tests"
done
rm -f "$LOG"
exit $STATUS

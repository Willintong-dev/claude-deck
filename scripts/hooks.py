import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"
COMMAND = str(Path.home() / ".claude-deck" / "bin" / "deck-hook")
EVENTS = {
    "SessionStart": False,
    "UserPromptSubmit": True,
    "Notification": True,
    "Stop": True,
    "SubagentStop": True,
    "SessionEnd": False,
}


def is_deck_group(group):
    return any(hook.get("command") == COMMAND for hook in group.get("hooks", []))


def install(hooks):
    for event, run_async in EVENTS.items():
        groups = hooks.setdefault(event, [])
        existing = [hook for group in groups for hook in group.get("hooks", []) if hook.get("command") == COMMAND]
        if existing:
            for hook in existing:
                hook["async"] = run_async
            continue
        groups.append({"hooks": [{"type": "command", "command": COMMAND, "timeout": 5, "async": run_async}]})


def remove(hooks):
    for event in list(hooks):
        hooks[event] = [group for group in hooks[event] if not is_deck_group(group)]
        if not hooks[event]:
            del hooks[event]


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "install"
    settings = json.loads(SETTINGS.read_text())
    backup = SETTINGS.with_name(f"settings.json.bak-claude-deck-{datetime.now():%Y%m%d%H%M%S}")
    shutil.copy2(SETTINGS, backup)
    hooks = settings.setdefault("hooks", {})
    if action == "remove":
        remove(hooks)
    else:
        install(hooks)
    SETTINGS.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
    print(f"{action}: ok (backup {backup})")


if __name__ == "__main__":
    main()

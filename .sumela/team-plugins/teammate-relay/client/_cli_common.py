"""Shared bootstrap for the thin ask/inbox/answer CLI wrappers."""
import json
import os
import sys

# Make the plugin root importable when invoked as a script (python client/ask.py ...).
_PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PLUGIN_ROOT not in sys.path:
    sys.path.insert(0, _PLUGIN_ROOT)


def runtime_dir() -> str:
    return os.environ.get("RELAY_RUNTIME", os.path.join(".sumela", ".relay"))


def role_map() -> dict:
    """The committed, CODEOWNERS-gated team role map (domain -> [member_ids])."""
    path = os.environ.get(
        "RELAY_ROLES",
        os.path.join(".sumela", "team-plugins", "teammate-relay", "roles.json"),
    )
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    return {}

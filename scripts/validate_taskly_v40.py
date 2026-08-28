from __future__ import annotations

import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import yaml
except Exception as exc:  # pragma: no cover
    raise SystemExit(f"PyYAML is required for validation: {exc}")

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "taskly_mobile"
LIB = MOBILE / "lib"

errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def strip_dart(text: str) -> str:
    # Removes comments and string bodies while preserving line structure and delimiters outside strings.
    out: list[str] = []
    i = 0
    quote: str | None = None
    triple = False
    raw = False
    while i < len(text):
        if quote is not None:
            marker = quote * (3 if triple else 1)
            if text.startswith(marker, i):
                out.extend(" " * len(marker))
                i += len(marker)
                quote = None
                triple = False
                raw = False
            elif text[i] == "\\" and not raw:
                out.append(" ")
                i += 1
                if i < len(text):
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            else:
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            if end < 0:
                out.extend(" " * (len(text) - i))
                break
            out.extend(" " * (end - i))
            out.append("\n")
            i = end + 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = len(text) - 2 if end < 0 else end
            block = text[i : end + 2]
            out.extend("\n" if c == "\n" else " " for c in block)
            i = end + 2
            continue
        is_raw = text[i] in "rR" and i + 1 < len(text) and text[i + 1] in "'\""
        start = i + 1 if is_raw else i
        if text[start] in "'\"":
            raw = is_raw
            quote = text[start]
            triple = text.startswith(quote * 3, start)
            marker_len = 3 if triple else 1
            out.extend(" " * ((start - i) + marker_len))
            i = start + marker_len
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


pairs = {"(": ")", "[": "]", "{": "}"}
for dart in sorted(LIB.rglob("*.dart")):
    text = dart.read_text(encoding="utf-8")
    clean = strip_dart(text)
    stack: list[tuple[str, int]] = []
    for line_no, line in enumerate(clean.splitlines(), 1):
        for char in line:
            if char in pairs:
                stack.append((char, line_no))
            elif char in pairs.values():
                if not stack or pairs[stack[-1][0]] != char:
                    errors.append(f"Unbalanced {char} in {dart.relative_to(ROOT)}:{line_no}")
                    stack.clear()
                    break
                stack.pop()
    if stack:
        errors.append(f"Unclosed {stack[-1][0]} in {dart.relative_to(ROOT)}:{stack[-1][1]}")

    for match in re.finditer(r"^import\s+['\"]([^'\"]+)['\"]", text, re.MULTILINE):
        target = match.group(1)
        if target.startswith("."):
            resolved = (dart.parent / target).resolve()
            require(resolved.is_file(), f"Missing relative import {target} from {dart.relative_to(ROOT)}")

pubspec = yaml.safe_load((MOBILE / "pubspec.yaml").read_text(encoding="utf-8"))
deps = pubspec.get("dependencies", {})
for name in [
    "firebase_core", "firebase_messaging", "flutter_local_notifications",
    "image_picker", "receive_sharing_intent", "flutter_contacts",
    "file_selector", "url_launcher", "shared_preferences", "mime",
]:
    require(name in deps, f"Missing dependency: {name}")
require("fonts" not in pubspec.get("flutter", {}), "Custom fonts remain in pubspec; system font requirement is not met")

ET.parse(MOBILE / "android/app/src/main/AndroidManifest.xml")
for plist in [
    MOBILE / "ios/Runner/Info.plist",
    MOBILE / "ios/Runner/Runner.entitlements",
    MOBILE / "ios/Share Extension/Info.plist",
    MOBILE / "ios/Share Extension/Share Extension.entitlements",
]:
    with plist.open("rb") as handle:
        plistlib.load(handle)

required_files = [
    LIB / "core/notifications/push_notification_service.dart",
    LIB / "core/files/attachment_policy.dart",
    LIB / "providers/theme_provider.dart",
    LIB / "screens/contact_info_screen.dart",
    LIB / "screens/forward_message_sheet.dart",
    LIB / "services/incoming_share_service.dart",
    ROOT / "supabase/functions/notify-message-recipients/index.ts",
    ROOT / "supabase/migrations/20260806_taskly_v40_social_mobile.sql",
]
for path in required_files:
    require(path.is_file(), f"Required file missing: {path.relative_to(ROOT)}")

manifest = (MOBILE / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
require("android.intent.action.SEND" in manifest, "Android share intent missing")
require("android:launchMode=\"singleTask\"" in manifest, "Android share launch mode missing")
require("android.permission.POST_NOTIFICATIONS" in manifest, "Android notification permission missing")

sql = (ROOT / "supabase/migrations/20260806_taskly_v40_social_mobile.sql").read_text(encoding="utf-8")
for token in [
    "taskly_visible_task_ids_v40", "taskly_register_device_token_v40",
    "taskly_channel_messages_v40", "taskly_create_message_notifications_v40",
    "forwarded_from_message_id", "shared_contact_profile_id",
]:
    require(token in sql, f"SQL feature missing: {token}")
require("notifications_type_v40_check" not in sql, "Restrictive notification type constraint remains")

secret_patterns = [
    re.compile(r"sk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
    re.compile(r'"private_key"\s*:\s*"-----BEGIN PRIVATE KEY'),
]
for path in ROOT.rglob("*"):
    if not path.is_file() or any(part in {".git", "build", ".dart_tool", "node_modules"} for part in path.parts):
        continue
    if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".jar", ".zip", ".webp"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        continue
    for pattern in secret_patterns:
        require(pattern.search(text) is None, f"Possible secret found in {path.relative_to(ROOT)}")

for forbidden in [
    MOBILE / "config/prod.json",
    MOBILE / "android/local.properties",
    MOBILE / "ios/Flutter/Generated.xcconfig",
    MOBILE / "ios/Flutter/flutter_export_environment.sh",
]:
    require(not forbidden.exists(), f"Machine-private file must not be shipped: {forbidden.relative_to(ROOT)}")

if errors:
    print("Taskly v4.0 validation failed:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print("Taskly v4.0 static validation passed.")

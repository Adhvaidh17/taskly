#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DART_ROOT = ROOT / "taskly_mobile" / "lib" / "v61"


def strip_dart(text: str) -> str:
    out: list[str] = []
    i = 0
    mode = "code"
    quote = ""
    triple = False
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if mode == "code":
            if c == "/" and n == "/":
                mode = "line"
                out.extend("  ")
                i += 2
                continue
            if c == "/" and n == "*":
                mode = "block"
                out.extend("  ")
                i += 2
                continue
            if c in "'\"":
                quote = c
                triple = text[i:i+3] == c * 3
                mode = "string"
                width = 3 if triple else 1
                out.extend(" " * width)
                i += width
                continue
            out.append(c)
            i += 1
            continue
        if mode == "line":
            if c == "\n":
                mode = "code"
                out.append("\n")
            else:
                out.append(" ")
            i += 1
            continue
        if mode == "block":
            if c == "*" and n == "/":
                mode = "code"
                out.extend("  ")
                i += 2
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        if mode == "string":
            if c == "\\":
                out.append(" ")
                if i + 1 < len(text):
                    out.append(" ")
                i += 2
                continue
            if triple and text[i:i+3] == quote * 3:
                out.extend("   ")
                i += 3
                mode = "code"
                continue
            if not triple and c == quote:
                out.append(" ")
                i += 1
                mode = "code"
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
    return "".join(out)


def check_balance(path: Path) -> list[str]:
    text = strip_dart(path.read_text(encoding="utf-8"))
    pairs = {')': '(', ']': '[', '}': '{'}
    stack: list[tuple[str, int]] = []
    errors: list[str] = []
    for index, ch in enumerate(text):
        if ch in "([{":
            stack.append((ch, index))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                errors.append(f"{path.name}: unexpected {ch} at {index}")
                break
            stack.pop()
    if stack:
        errors.append(f"{path.name}: unclosed {stack[-1][0]} at {stack[-1][1]}")
    return errors


def main() -> int:
    errors: list[str] = []
    for path in sorted(DART_ROOT.glob("*.dart")):
        errors += check_balance(path)
        text = path.read_text(encoding="utf-8")
        if "FontWeight.w750" in text:
            errors.append(f"{path.name}: invalid FontWeight.w750")
        for rel in re.findall(r"import\s+'([^']+)'", text):
            if rel.startswith(("package:", "dart:")):
                continue
            target = (path.parent / rel).resolve()
            # Existing-v60 imports intentionally point outside this overlay.
            if "/v61/" in str(target).replace('\\', '/') and not target.exists():
                errors.append(f"{path.name}: missing relative import {rel}")

    migration = ROOT / "supabase" / "migrations" / "20260828093000_taskly_v61_private_chat_cleanup.sql"
    sql = migration.read_text(encoding="utf-8").lower()
    if sql.count("begin;") != 1 or sql.count("commit;") != 1:
        errors.append("migration: expected exactly one begin;/commit;")
    if "taskly_block_persistent_chat_v61" not in sql:
        errors.append("migration: transcript-block trigger missing")
    if "'mention'" not in sql:
        errors.append("migration: mention notification privacy guard missing")

    if errors:
        print("FAILED")
        for error in errors:
            print(" -", error)
        return 1
    print(f"PASS: {len(list(DART_ROOT.glob('*.dart')))} Dart overlay files + migration static checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())

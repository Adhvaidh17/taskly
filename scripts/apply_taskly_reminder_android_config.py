#!/usr/bin/env python3
"""Apply the Android Gradle settings required by scheduled local notifications."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "taskly_mobile" / "android" / "app"
KTS = APP / "build.gradle.kts"
GROOVY = APP / "build.gradle"
DEPENDENCY = "com.android.tools:desugar_jdk_libs:2.1.4"


def insert_inside_named_block(text: str, block_name: str, line: str) -> str:
    pattern = re.compile(rf"(^\s*{re.escape(block_name)}\s*\{{\s*$)", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        raise RuntimeError(f"Could not find {block_name} block")
    indent = re.match(r"\s*", match.group(1)).group(0) + "    "
    return text[: match.end()] + f"\n{indent}{line}" + text[match.end() :]


def patch_kts(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    changed = False

    if "isCoreLibraryDesugaringEnabled = true" not in text:
        text = insert_inside_named_block(
            text,
            "compileOptions",
            "isCoreLibraryDesugaringEnabled = true",
        )
        changed = True

    if not re.search(r"\bmultiDexEnabled\s*=\s*true\b", text):
        text = insert_inside_named_block(text, "defaultConfig", "multiDexEnabled = true")
        changed = True

    if DEPENDENCY not in text:
        dependency_line = f'coreLibraryDesugaring("{DEPENDENCY}")'
        if re.search(r"^\s*dependencies\s*\{\s*$", text, re.MULTILINE):
            text = insert_inside_named_block(text, "dependencies", dependency_line)
        else:
            text = text.rstrip() + f"\n\ndependencies {{\n    {dependency_line}\n}}\n"
        changed = True

    if changed:
        path.write_text(text, encoding="utf-8")
        print(f"Updated {path}")
    else:
        print(f"Already configured: {path}")


def patch_groovy(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    changed = False

    if "coreLibraryDesugaringEnabled true" not in text:
        text = insert_inside_named_block(
            text,
            "compileOptions",
            "coreLibraryDesugaringEnabled true",
        )
        changed = True

    if not re.search(r"\bmultiDexEnabled\s+true\b", text):
        text = insert_inside_named_block(text, "defaultConfig", "multiDexEnabled true")
        changed = True

    if DEPENDENCY not in text:
        dependency_line = f"coreLibraryDesugaring '{DEPENDENCY}'"
        if re.search(r"^\s*dependencies\s*\{\s*$", text, re.MULTILINE):
            text = insert_inside_named_block(text, "dependencies", dependency_line)
        else:
            text = text.rstrip() + f"\n\ndependencies {{\n    {dependency_line}\n}}\n"
        changed = True

    if changed:
        path.write_text(text, encoding="utf-8")
        print(f"Updated {path}")
    else:
        print(f"Already configured: {path}")


def main() -> None:
    if KTS.exists():
        patch_kts(KTS)
        return
    if GROOVY.exists():
        patch_groovy(GROOVY)
        return
    raise SystemExit(
        "Android app Gradle file was not found. Run this after extracting the patch "
        "into C:\\Projects\\taskly_flutter_supabase."
    )


if __name__ == "__main__":
    main()

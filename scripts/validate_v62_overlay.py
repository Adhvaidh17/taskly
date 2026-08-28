from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
v62 = root / 'taskly_mobile' / 'lib' / 'v62'
required = {
    'taskly_ai_theme_v62.dart': ['TasklyAiThemeV62', 'light()', 'dark()'],
    'ai_universe_shell_v62.dart': ['AiUniverseShellV62', 'TasklyIntelligenceOrbV62', 'AiGlassCardV62'],
    'ai_phone_login_screen_v62.dart': ['AiPhoneLoginScreenV62', 'onRequestOtp', 'onVerifyOtp'],
    'ai_restore_or_transfer_screen_v62.dart': ['AiRestoreOrTransferScreenV62', 'Transfer from old phone', 'Google Drive'],
    'ai_onboarding_screen_v62.dart': ['AiOnboardingScreenV62', 'Chats stay with you'],
    'new_chat_hub_v62.dart': ['NewChatHubV62', 'Create group', 'Join group'],
    'chat_info_screen_v62.dart': ['ChatInfoScreenV62', 'Media, links and docs', 'Chat lock', 'Advanced chat privacy'],
    'ai_chat_list_shell_v62.dart': ['AiChatListShellV62', 'New chat'],
    'ai_message_action_sheet_v62.dart': ['showMessageActionSheetV62', 'Reply', 'Forward', 'Delete'],
    'ai_app_chrome_v62.dart': ['AiBottomNavigationV62', 'AiChatComposerSurfaceV62'],
    'profile_chat_settings_section_v62.dart': ['ProfileChatSettingsSectionV62', 'Chat backup'],
    'ai_page_scaffold_v62.dart': ['AiPageScaffoldV62', 'AiUniverseShellV62'],
}

errors = []
for name, needles in required.items():
    path = v62 / name
    if not path.exists():
        errors.append(f'missing {name}')
        continue
    text = path.read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            errors.append(f'{name}: missing marker {needle!r}')
    if re.search(r'FontWeight\.w(?:650|750)', text):
        errors.append(f'{name}: invalid FontWeight alias found')

# Crude delimiter check after removing strings/comments. This is not a Dart
# compiler but catches the most common damaged-overlay mistakes.
def scrub(src: str) -> str:
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//.*', '', src)
    src = re.sub(r"'''(?:.|\n)*?'''", "''", src)
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\])*'", "''", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    return src

pairs = {')': '(', ']': '[', '}': '{'}
for path in v62.glob('*.dart'):
    stack = []
    for i, ch in enumerate(scrub(path.read_text(encoding='utf-8'))):
        if ch in '([{':
            stack.append(ch)
        elif ch in ')]}':
            if not stack or stack.pop() != pairs[ch]:
                errors.append(f'{path.name}: unbalanced delimiter near character {i}')
                break
    else:
        if stack:
            errors.append(f'{path.name}: unclosed delimiters {stack[-8:]}')

migration = root / 'supabase' / 'migrations' / '20260828093000_taskly_v61_private_chat_cleanup.sql'
if not migration.exists():
    errors.append('missing v61 privacy migration')

if errors:
    print('V62 overlay validation FAILED:')
    for error in errors:
        print(' -', error)
    sys.exit(1)

print(f'V62 overlay validation OK: {len(required)} UI files + v61 privacy migration')

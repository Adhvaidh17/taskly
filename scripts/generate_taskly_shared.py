#!/usr/bin/env python3
from pathlib import Path
import json, re
ROOT=Path(__file__).resolve().parents[1]
contract=json.loads((ROOT/'shared/taskly_contract.json').read_text(encoding='utf-8'))
web=ROOT/'taskly_web'
mobile=ROOT/'taskly_mobile'

def ts_obj(obj, indent=0):
    return json.dumps(obj, indent=2, ensure_ascii=False).replace('"', "'")

if web.exists():
    p=web/'src/generated/taskly-contract.ts'; p.parent.mkdir(parents=True,exist_ok=True)
    raw=json.dumps(contract, indent=2, ensure_ascii=False)
    # valid TS object from JSON is also valid JS/TS
    p.write_text('// Generated from shared/taskly_contract.json. Do not edit.\nexport const TASKLY_CONTRACT = '+raw+' as const;\n',encoding='utf-8')

p=mobile/'lib/generated/taskly_contract.g.dart'; p.parent.mkdir(parents=True,exist_ok=True)
lines=['// Generated from shared/taskly_contract.json. Do not edit.','abstract final class TasklyContract {',f"  static const version = {contract['version']!r};",f"  static const domain = {contract['domain']!r};",f"  static const desktopMinWidth = {contract['desktopMinWidth']};",f"  static const storageBucket = {contract['storageBucket']!r};"]
for group in ('rpc','functions'):
    for k,v in contract[group].items(): lines.append(f"  static const {group}{k[:1].upper()+k[1:]} = {v!r};")
lines.append('}')
p.write_text('\n'.join(lines)+'\n',encoding='utf-8')

# Sync the core Flutter palette to web where possible. Defaults are current Taskly palette.
colors={'accent':'6D5CE7','danger':'E05252','warning':'E59A23','success':'169B72','info':'3B82F6'}
theme=mobile/'lib/core/theme/app_theme.dart'
if theme.exists():
    text=theme.read_text(encoding='utf-8')
    for name in list(colors):
        m=re.search(rf'\b{name}\b[^\n]*Color\(0xFF([0-9A-Fa-f]{{6}})\)',text)
        if m: colors[name]=m.group(1).upper()
if web.exists():
    css=web/'src/styles/generated-theme.css'; css.parent.mkdir(parents=True,exist_ok=True)
    css.write_text('/* Generated from Flutter AppTheme/shared defaults. */\n:root {\n'+''.join(f'  --taskly-{k}: #{v};\n' for k,v in colors.items())+'}\n',encoding='utf-8')
print('Taskly shared contract/theme generated for Flutter and Web.')

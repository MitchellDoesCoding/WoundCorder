"""Ensure every bundled education paragraph has both translations; preserve model keys/assets."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
base = root / 'LiDARDepth/Model/Code/Codes'
catalog = json.loads((base / 'Localization/wound-localization.json').read_text())
def prose(value, key=''):
    if key in ('images', 'references', 'link'):
        return
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from prose(item, key)
    elif isinstance(value, dict):
        for child, item in value.items():
            yield from prose(item, child)
paragraphs = set()
for path in (base / 'WoundEducation').glob('*.json'):
    paragraphs.update(prose(json.loads(path.read_text())))
for language in ('es', 'fr'):
    missing = paragraphs - catalog[language].keys()
    assert not missing, (language, sorted(missing))
    assert all(catalog[language][key].strip() for key in paragraphs)
print(f'PASS: all {len(paragraphs)} education strings translated in Spanish and French')

# Catch newly introduced literal UI copy without a bundled translation.
import re
allowed = {'WoundCorder', 'cm', 'kg', 'cm²', 'cm³', '', 'R', 'L', '?', '—'}
checked = 0
for path in (root / 'LiDARDepth').rglob('*.swift'):
    if path.name == 'WoundLocalization.swift':
        continue
    for match in re.finditer(r'WoundL10n\.text\("((?:\\.|[^"\\])*)"\)', path.read_text()):
        literal = match.group(1)
        if '\\(' in literal or not re.search('[A-Za-z]', literal):
            continue
        literal = literal.replace('\\n', '\n').replace('\\"', '"')
        for language in ('es', 'fr'):
            template_match = any('%@' in key and re.fullmatch(re.escape(key).replace('%@', r'[^\n]*?'), literal) for key in catalog[language])
            assert literal in allowed or literal in catalog[language] or template_match, (path, language, literal)
        checked += 1
print(f'PASS: {checked} static UI string uses have translations or explicit proper-name/unit exemptions')

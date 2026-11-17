"""Fail when app-owned Chinese UI text is reintroduced; exclude stored IDs."""
from pathlib import Path
import re,sys
root=Path(__file__).resolve().parents[1]
exceptions={
 'CompanionStore.swift': [r'^\s*var (recognition|speech) = '],
 'ArchiveView.swift': [r'var mode = ',r'\.tag\(',r'if mode == '],
 'ToolsView.swift': [r'var mode = ',r'\.tag\(',r'if mode == '],
 'ConversationView.swift': [r'\.tag\(']
}
failures=[]; preserved=0
for p in (root/'apps/RayNeoCompanion/Sources').glob('*.swift'):
 for n,line in enumerate(p.read_text().splitlines(),1):
  if not re.search('[\u3400-\u9fff]',line): continue
  if any(re.search(rule,line) for rule in exceptions.get(p.name,[])):
   preserved+=1
  else: failures.append(f'{p.name}:{n}: {line.strip()}')
print(f'App UI audit: {len(failures)} untranslated lines; {preserved} legacy selection/storage lines preserved.')
for failure in failures: print(failure)
sys.exit(bool(failures))

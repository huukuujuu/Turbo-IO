from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
mapping={}
for line in ((root/'localizations/ko.tsv').read_text() + '\n' + (root/'localizations/ko-review.tsv').read_text()).splitlines():
 if line:
  a,b=line.split('\t',1); mapping[a]=b
paths=list((root/'apps/RayNeoCompanion/Sources').glob('*.swift'))
paths.append(root/'core-probe/Sources/App.swift')
paths.append(root/'core-probe/Sources/CloudVoiceSettings.swift')
paths += [root/'apps/RayNeoCompanion/Sources'/n for n in ['DisplayObserverServer.swift','AlwaysOnLocalProbe.swift','ManualRecordingASR.swift']]
for p in paths:
 s=p.read_text()
 # Preserve persisted selection values and comparisons; only labels change.
 protected=[]
 def protect(m):
  protected.append(m.group(0)); return f'__KO_PRESERVE_{len(protected)-1}__'
 s=re.sub(r'\.tag\("[^"\n]*"\)|(?:mode\s*==\s*|var mode = |var recognition = |var speech = )"[^"\n]*"',protect,s)
 for cn,ko in sorted(mapping.items(),key=lambda item:len(item[0]),reverse=True):
  s=s.replace('"'+cn+'"','"'+ko+'"')
 for i,v in enumerate(protected): s=s.replace(f'__KO_PRESERVE_{i}__',v)
 p.write_text(s)
print(f'Applied {len(mapping)} translations to {len(paths)} app source files.')
# Translate interpolated view labels without touching selection tags or wire data.
fragments=[line.split('\t',1) for line in (root/'localizations/fragments.tsv').read_text().splitlines() if line]
for p in (root/'apps/RayNeoCompanion/Sources').glob('*View*.swift'):
 s=p.read_text()
 for cn,ko in sorted(fragments,key=lambda item:len(item[0]),reverse=True):
  s=s.replace(cn,ko)
 p.write_text(s)

# Apply reviewed status/export text fragments to app source only.
review_pairs=[line.split('\t',1) for line in (root/'localizations/review-fragments.tsv').read_text().splitlines() if line]
for p in (root/'apps/RayNeoCompanion/Sources').glob('*.swift'):
 s=p.read_text()
 for cn,ko in sorted(review_pairs,key=lambda item:len(item[0]),reverse=True):
  s=s.replace(cn,ko)
 p.write_text(s)

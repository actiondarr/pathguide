"""Regenerate Flutter labels from the stable project class registry."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
classes = json.loads((ROOT / 'configs/classes.json').read_text())['classes']
assert [c['id'] for c in classes] == list(range(len(classes)))
order = [c['id'] for c in sorted(classes, key=lambda c: (
    not c['announced'], c['priority'], c['id']))]
target = ROOT / 'app/lib/vision/labels.dart'
current = target.read_text()
header = current[:current.index('const List<Label> kLabels')]
rows = []
for item in classes:
    values = [f"    id: {item['id']},"]
    for key, field in [('nameEn','name_en'),('nameZh','name_zh'),('group','group'),('priority','priority')]:
        values.append(f"    {key}: {json.dumps(item[field], ensure_ascii=False)},")
    values.append(f"    announced: {str(item['announced']).lower()},")
    rows.append('  Label(\n' + '\n'.join(values) + '\n  ),')
footer = f'''\n];

/// 項目類別表大小；模型的輸出類別數另由模型清單聲明。
const int kNumClasses = {len(classes)};

/// 播報優先級順序。
const List<int> kAnnouncementOrder = <int>{order};

/// 按 id 取類別。越界時返回 null。
Label? labelOf(int id) => (id >= 0 && id < kLabels.length) ? kLabels[id] : null;
'''
target.write_text(header + 'const List<Label> kLabels = <Label>[\n' + '\n'.join(rows) + footer)
(ROOT / 'app/assets/labels.json').write_text(json.dumps({
    'generated_from': 'configs/classes.json',
    'note': '由 scripts/gen_dart_labels.py 生成，請勿手工編輯。',
    'num_classes': len(classes), 'announcement_order': order, 'labels': classes,
}, ensure_ascii=False, indent=2) + '\n')

"""Self-contained progress diagram; no state inference or state writes."""
import html

from check_spec import (JST, deadline_remaining_days, evaluate_event_deadline,
                        evaluate_application_deadlines)
from journey_map import (PROVIDER_LABEL, BOX_W, COLOR_BOX, COLOR_BOX_STROKE, COLOR_TEXT,
                         COLOR_SUB, COLOR_EDGE, COLOR_DEADLINE, COLOR_GATE,
                         wrap_text, svg_text_lines, relative_deadline_text)

STATUS = {
    'done': ('✓ 済み', '#ecfdf5', '#047857'),
    'current': ('▶ いまここ', '#1e293b', '#1e293b'),
    'todo': ('これから', COLOR_BOX, COLOR_BOX_STROKE),
    'stale': ('! やり直し', '#fff1f2', COLOR_DEADLINE),
    'optional': ('任意', '#ffffff', COLOR_BOX_STROKE),
    'unknown': ('? 確認できません', COLOR_GATE, COLOR_BOX_STROKE),
}
PENDING = '補助金のデータが確定すると、外部の窓口の手続きと期限がここに出ます。'
EXTERNAL_NOTE = '外部の窓口での手続きは、この図では進み具合を追っていません。期限はご自身で確かめてください。'


def deadline_text(evaluation, now):
    date = evaluation.raw_date
    if evaluation.raw_time:
        date += ' ' + evaluation.raw_time
    return date + ('・期限を過ぎています' if evaluation.expired else
                   '・残り {} 日'.format(deadline_remaining_days(evaluation.raw_date, now)))


def external_cards(spec, now):
    events = {e['event_id']: e for e in spec.get('schedule', [])}
    cards = []
    for item in spec.get('deliverables', []):
        if item.get('produced_by') != 'external':
            continue
        event = events.get(item.get('due_event_id'), {})
        evaluation = evaluate_event_deadline(event, now)
        due = (deadline_text(evaluation, now) if evaluation else
               relative_deadline_text(event) or '期限は要確認')
        cards.append([item['name'], '窓口: ' + (item.get('issuer') or '要確認'), due])
    for evaluation in evaluate_application_deadlines(spec, now):
        cards.append(['申請締切', deadline_text(evaluation, now)])
    return cards


def render_html(result, flow, now, numbers, spec=None, confirmed=False):
    """Render the progress JSON and lane definitions without modifying either."""
    title = '申請の進み具合'
    if spec:
        title += '｜' + str(spec.get('name') or '')
        if spec.get('round'):
            title += ' ' + str(spec['round'])
    lanes = flow['lanes']
    lane_width, gap, margin = BOX_W + 24, 16, 20
    width = margin * 2 + len(lanes) * (lane_width + gap) - gap
    centers = {lane['lane_id']: margin + i * (lane_width + gap) + lane_width / 2
               for i, lane in enumerate(lanes)}
    parts, boxes = [], []

    def text(x, y, value, size=14, color=COLOR_TEXT, weight='normal', limit=21):
        lines = wrap_text(str(value), limit, max(1, len(str(value))))
        parts.extend(svg_text_lines(x, y, lines, size, color, weight, line_height=20))
        return y + 20 * len(lines)

    # Each row follows the command order, independently of journey-map topology.
    y = 80
    positions = []
    for step in result['steps']:
        x, top = centers[step['lane']], y
        status = step['status']
        label, fill, stroke = STATUS[status]
        fg = '#ffffff' if status == 'current' else COLOR_TEXT
        parts.append('<g data-step-id="{}" data-status="{}"><title>{}</title>'.format(
            html.escape(step['step_id'], quote=True), html.escape(status, quote=True),
            html.escape(step.get('reason') or step['label'])))
        # Insert the rectangle behind text once its full height is known.
        rect_at = len(parts)
        prefix = '任意 ' if step['optional'] else '{}. '.format(numbers[step['step_id']])
        y = text(x, y + 25, prefix + step['label'], color=fg, weight='bold')
        y = text(x, y, ' または '.join('/' + c for c in step['commands']) or 'ご自身で提出',
                 size=13, color=fg)
        y = text(x, y, label, color=fg, weight='bold')
        if step['step_id'] == 'draft-section' and step.get('detail'):
            detail = step['detail']
            y = text(x, y, '{}/{} セクション'.format(detail['count'], detail['total']), color=fg)
        if step.get('human_gate'):
            gate = 'あなたが確認する工程' if status == 'done' else 'あなたの確認が必要'
            if (step.get('detail') or {}).get('confirmed_by') == 'provider':
                gate = PROVIDER_LABEL
            y = text(x, y, gate, size=12, color=fg)
        bottom = y + 2
        parts.insert(rect_at, '<rect x="{}" y="{}" width="{}" height="{}" rx="10" '
                     'fill="{}" stroke="{}" stroke-width="{}"{}/>'.format(
                         x - BOX_W / 2, top, BOX_W, bottom - top, fill, stroke,
                         4 if status == 'current' else 1.5,
                         ' stroke-dasharray="6 4"' if status == 'optional' else ''))
        y = bottom
        if status == 'stale':
            reason = wrap_text(step['reason'], 24, 1)
            parts.extend(svg_text_lines(x, y + 18, reason, 12, COLOR_DEADLINE))
            y += 26
        parts.append('</g>')
        positions.append((x, top, bottom, y))
        y += 44
    steps_bottom = y
    for previous, following in zip(positions, positions[1:]):
        x1, _, bottom, after_note = previous
        x2, top, _, _ = following
        mid = (after_note + top) / 2
        # Explicit arrowheads avoid CSS url() references.
        boxes.append('<path d="M {} {} V {} H {} V {}" fill="none" stroke="{}" '
                     'stroke-width="2"/>'.format(x1, after_note + 4, mid, x2, top - 8, COLOR_EDGE))
        boxes.append('<polygon points="{},{} {},{} {},{}" fill="{}"/>'.format(
            x2 - 5, top - 10, x2 + 5, top - 10, x2, top - 3, COLOR_EDGE))
    y, x = 80, centers['external']
    if spec and confirmed:
        for card in external_cards(spec, now):
            top, rect_at = y, len(parts)
            y += 25
            for i, value in enumerate(card):
                y = text(x, y, value, weight='bold' if i == 0 else 'normal')
            parts.insert(rect_at, '<rect x="{}" y="{}" width="{}" height="{}" rx="10" '
                         'fill="{}" stroke="{}"/>'.format(
                             x - BOX_W / 2, top, BOX_W, y - top + 4, COLOR_BOX, COLOR_BOX_STROKE))
            y += 30
        y = text(x, y + 10, EXTERNAL_NOTE, size=13, color=COLOR_SUB)
    else:
        y = text(x, y + 25, PENDING, color=COLOR_SUB)
    height = max(steps_bottom, y + 30)
    background = []
    for lane in lanes:
        x = centers[lane['lane_id']]
        background.append('<rect x="{}" y="8" width="{}" height="{}" rx="12" '
                          'fill="#f8fafc" stroke="#e2e8f0"/>'.format(
                              x - lane_width / 2, lane_width, height - 16))
        background.extend(svg_text_lines(x, 42, [lane['label']], 16, COLOR_TEXT, 'bold'))
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {} {}" role="img" aria-label="{}">{}</svg>'.format(
        width, height, html.escape(title, quote=True), '\n'.join(background + boxes + parts))
    return '''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><style>
* {{box-sizing:border-box}} body {{margin:0;background:#fff;color:#1e293b;font-family:sans-serif}}
main {{max-width:1120px;margin:auto;padding:20px}} h1 {{font-size:24px}}
p {{line-height:1.7;overflow-wrap:anywhere}} svg {{display:block;width:100%;height:auto}}
.legend {{padding:12px;background:#f1f5f9;border-radius:10px}}
</style></head><body><main><h1>{title}</h1><p>{line}</p>
<p>{display_lines}<br>作成日: {date}（日本時間）</p>
{svg}
<p class="legend">凡例: ✓ 済み ／ ▶ いまここ（太枠） ／ これから ／ ! やり直し ／ 任意（破線） ／ ? 確認できません</p>
<p>この図は進み具合の目安です。済みの印は、ご本人の確認や提出の判断の代わりにはなりません。日付・手続き・要件の正は公式の公募要領です。</p>
<p>作成者は申請者ご本人です。AI は補助・壁打ちを行います。申請代行・代理提出は行いません。</p>
<p>ブラウザで開いたままの場合は、再読み込みすると最新になります。</p>
</main></body></html>'''.format(title=html.escape(title), line=html.escape(result['line']),
                              display_lines='<br>'.join(html.escape(v) for v in result['display_lines']), svg=svg,
                              date=now.astimezone(JST).strftime('%Y-%m-%d'))

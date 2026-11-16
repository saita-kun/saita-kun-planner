"""Format relative deadlines without calculating dates or converting units."""

import typing

Json = typing.Any


def relative_deadline_text(event: Json) -> typing.Optional[str]:
    relative = event.get("relative") if isinstance(event, dict) else None
    if not isinstance(relative, dict):
        return None
    if set(relative) != {"anchor", "offset", "direction"}:
        return None
    if relative["direction"] not in ("within_after", "before", None):
        return None
    anchor = relative.get("anchor")
    if not isinstance(anchor, str) or not anchor.strip():
        return None
    anchor = anchor.strip()
    offset = relative.get("offset")
    if offset is not None:
        if not isinstance(offset, dict) or set(offset) != {"value", "unit"}:
            return None
        value = offset["value"]
        unit = {"day": "日", "month": "か月", "year": "年"}.get(str(offset["unit"]))
        if type(value) is not int or value < 0 or unit is None:
            return None
        amount = f"{value}{unit}"
    direction = relative.get("direction")
    if offset is not None:
        if direction == "within_after":
            return f"{anchor}から{amount}以内"
        if direction == "before":
            return f"{anchor}の{amount}前まで"
        return f"{anchor}起点・{amount}（前後は要確認）"
    if offset is None:
        if direction == "within_after":
            return f"{anchor}以降"
        if direction == "before":
            return f"{anchor}より前"
        return f"{anchor}起点"
    return None


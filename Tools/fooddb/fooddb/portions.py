"""Turning FDC food_portion rows into (label, grams, seq) rows."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from .fdc import FdcPortion

UNDETERMINED_UNIT_ID = 9999
UNDETERMINED_UNIT_NAME = "undetermined"


@dataclass(frozen=True)
class PortionRow:
    label: str
    grams: float
    seq: int


def format_amount(value: float) -> str:
    """Format 1.0 -> '1', 0.5 -> '0.5', 2.25 -> '2.25'."""
    text = f"{value:.6f}".rstrip("0").rstrip(".")
    return text if text not in ("", "-0") else "0"


def portion_label(portion: FdcPortion, unit_name: str | None) -> str:
    """Compose a household-measure label; empty string when nothing usable exists.

    With a real unit: "{amount} {unit}" plus ", {modifier}". With an undetermined
    or unknown unit, FDC puts the whole measure in portion_description (which
    already embeds the amount) or the measure minus the amount in modifier.
    """
    unit = unit_name.strip() if unit_name is not None else ""
    undetermined = (
        portion.measure_unit_id is None
        or portion.measure_unit_id == UNDETERMINED_UNIT_ID
        or not unit
        or unit.lower() == UNDETERMINED_UNIT_NAME
    )
    if undetermined:
        if portion.portion_description:
            return portion.portion_description
        if portion.modifier and portion.amount is not None:
            return f"{format_amount(portion.amount)} {portion.modifier}"
        return ""
    if portion.amount is None:
        return ""
    label = f"{format_amount(portion.amount)} {unit}"
    if portion.modifier:
        label = f"{label}, {portion.modifier}"
    return label


def build_portions(
    portions: Sequence[FdcPortion], unit_names: Mapping[int, str]
) -> list[PortionRow]:
    """Rows for one food: positive gram weight, non-empty label, unique (label, grams)."""
    rows: list[PortionRow] = []
    seen: set[tuple[str, float]] = set()
    for index, portion in enumerate(portions, start=1):
        if portion.gram_weight is None or portion.gram_weight <= 0:
            continue
        unit_name = None
        if portion.measure_unit_id is not None:
            unit_name = unit_names.get(portion.measure_unit_id)
        label = " ".join(portion_label(portion, unit_name).split())
        if not label:
            continue
        key = (label, portion.gram_weight)
        if key in seen:
            continue
        seen.add(key)
        seq = portion.seq_num if portion.seq_num is not None else index
        rows.append(PortionRow(label=label, grams=portion.gram_weight, seq=seq))
    return rows

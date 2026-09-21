from __future__ import annotations

import unittest

from fooddb.fdc import FdcPortion
from fooddb.portions import build_portions, format_amount, portion_label

UNITS = {1000: "cup", 1001: "tbsp", 9999: "undetermined"}


def portion(
    amount: float | None = 1.0,
    unit: int | None = 1000,
    desc: str = "",
    modifier: str = "",
    grams: float | None = 100.0,
    seq: int | None = 1,
) -> FdcPortion:
    return FdcPortion(
        fdc_id=1, seq_num=seq, amount=amount, measure_unit_id=unit,
        portion_description=desc, modifier=modifier, gram_weight=grams,
    )


class PortionLabelTests(unittest.TestCase):
    def test_format_amount(self) -> None:
        self.assertEqual(format_amount(1.0), "1")
        self.assertEqual(format_amount(0.5), "0.5")
        self.assertEqual(format_amount(2.25), "2.25")
        self.assertEqual(format_amount(0.333333), "0.333333")

    def test_plain_unit(self) -> None:
        self.assertEqual(portion_label(portion(1, 1001), "tbsp"), "1 tbsp")
        self.assertEqual(portion_label(portion(0.5, 1000), "cup"), "0.5 cup")
        self.assertEqual(portion_label(portion(None, 1000), "cup"), "")

    def test_unit_with_modifier(self) -> None:
        label = portion_label(portion(1, 1000, modifier="chopped"), "cup")
        self.assertEqual(label, "1 cup, chopped")

    def test_undetermined_description_is_verbatim(self) -> None:
        label = portion_label(portion(1, 9999, desc="1 medium", modifier="x"), "undetermined")
        self.assertEqual(label, "1 medium")

    def test_undetermined_modifier_gets_amount(self) -> None:
        label = portion_label(portion(1, 9999, modifier="slice"), "undetermined")
        self.assertEqual(label, "1 slice")
        label = portion_label(portion(0.5, 9999, modifier="cup, chopped"), "undetermined")
        self.assertEqual(label, "0.5 cup, chopped")
        label = portion_label(portion(1, 9999, modifier='medium (3" dia)'), "undetermined")
        self.assertEqual(label, '1 medium (3" dia)')

    def test_undetermined_without_usable_text_is_empty(self) -> None:
        self.assertEqual(portion_label(portion(1, 9999), "undetermined"), "")
        self.assertEqual(portion_label(portion(None, 9999, modifier="slice"), "undetermined"), "")

    def test_unknown_unit_id_treated_as_undetermined(self) -> None:
        self.assertEqual(portion_label(portion(1, 4242, modifier="large"), None), "1 large")
        self.assertEqual(portion_label(portion(2, None, modifier="large"), None), "2 large")

    def test_build_skips_zero_weight_empty_label_and_duplicates(self) -> None:
        rows = build_portions([
            portion(1, 1000, modifier="chopped", grams=125, seq=1),
            portion(1, 9999, grams=100, seq=2),                      # empty label
            portion(1, 9999, desc="1 small", grams=0, seq=3),        # zero grams
            portion(1, 1000, modifier="chopped", grams=125, seq=4),  # duplicate
            portion(2.25, 1000, grams=549, seq=None),                # seq from row order
        ], UNITS)
        self.assertEqual(
            [(r.label, r.grams, r.seq) for r in rows],
            [("1 cup, chopped", 125.0, 1), ("2.25 cup", 549.0, 5)],
        )


if __name__ == "__main__":
    unittest.main()

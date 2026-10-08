"""What every source has in common: an unzipped folder, an id and a version."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

FOUNDATION = "fdc_foundation"
SR_LEGACY = "fdc_sr_legacy"
CIQUAL = "ciqual"
BLS = "bls"

_DATE_RE = re.compile(r"\d{4}(?:-\d{2}(?:-\d{2})?)?")


@dataclass(frozen=True)
class Bundle:
    """One unzipped dataset, ready to read."""

    source: str
    root: Path
    version: str
    # Which sheet to read, when the source is a workbook with more than one.
    sheet: str | None = None


def version_from_path(path: Path, stop: Path) -> str:
    """Date or year in the folder name or its ancestors below `stop`; `stop` is never used.

    Publishers put the edition in the folder name their zip unpacks to, which is
    the only place a version is reliably written down.
    """
    for candidate in (path, *path.parents):
        if candidate == stop:
            break
        match = _DATE_RE.search(candidate.name)
        if match:
            return match.group(0)
    return "unknown"

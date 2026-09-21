"""Atomic file publishing shared by the sqlite, json and zip writers."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def default_mode() -> int:
    """0o666 masked by the process umask, i.e. what a plain open() would create."""
    mask = os.umask(0)
    os.umask(mask)
    return 0o666 & ~mask


def temp_beside(target: Path, suffix: str = ".tmp") -> Path:
    """Create an empty temp file in `target`'s directory; the caller publishes or removes it."""
    target.parent.mkdir(parents=True, exist_ok=True)
    handle, name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=suffix, dir=target.parent)
    os.close(handle)
    return Path(name)


def publish(temp: Path, target: Path) -> None:
    """Give `temp` normal permissions and rename it over `target` (a symlink is replaced)."""
    os.chmod(temp, default_mode())
    os.replace(temp, target)

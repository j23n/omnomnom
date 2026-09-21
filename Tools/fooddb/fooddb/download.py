"""Fetching the pinned FDC zips over https, verifying them and unzipping safely."""

from __future__ import annotations

import hashlib
import logging
import urllib.request
import zipfile
from dataclasses import dataclass
from http.client import HTTPMessage
from pathlib import Path, PurePosixPath
from typing import IO
from urllib.parse import urlparse

from .errors import DownloadError
from .fsutil import publish, temp_beside

log = logging.getLogger(__name__)

FDC_BASE = "https://fdc.nal.usda.gov/fdc-datasets/"
DEFAULT_FOUNDATION_URL = FDC_BASE + "FoodData_Central_foundation_food_csv_2025-04-24.zip"
DEFAULT_SR_LEGACY_URL = FDC_BASE + "FoodData_Central_sr_legacy_food_csv_2018-04.zip"

TIMEOUT_SECONDS = 60
MAX_EXTRACT_BYTES = 2 * 1024**3
_CHUNK = 1 << 20


@dataclass(frozen=True)
class Pin:
    """A download target with optional integrity expectations."""

    url: str
    size: int | None = None
    sha256: str | None = None

    @property
    def filename(self) -> str:
        return PurePosixPath(urlparse(self.url).path).name


# Fill in size and sha256 after the first verified download (see README, "Pinning hashes").
PINS: dict[str, Pin] = {
    "foundation": Pin(DEFAULT_FOUNDATION_URL),
    "sr_legacy": Pin(DEFAULT_SR_LEGACY_URL),
}


class HttpsOnlyRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Follow redirects only when they stay on https."""

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: HTTPMessage,
        newurl: str,
    ) -> urllib.request.Request | None:
        if urlparse(newurl).scheme != "https":
            raise DownloadError(f"refusing redirect to non-https URL: {newurl}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(path: Path, pin: Pin) -> str:
    """Check size and hash where pinned; on a mismatch delete the file and raise.

    Returns the computed sha256 either way.
    """
    size = path.stat().st_size
    if pin.size is not None and size != pin.size:
        path.unlink()
        raise DownloadError(
            f"{path.name}: size {size} does not match pinned {pin.size}; "
            "deleted the file, rerun to fetch it again"
        )
    digest = sha256_of(path)
    if pin.sha256 is None:
        log.warning(
            "%s: no pinned sha256, integrity NOT verified. Computed size=%d sha256=%s; "
            "paste both into PINS in fooddb/download.py to pin this file",
            path.name, size, digest,
        )
    elif digest.lower() != pin.sha256.lower():
        path.unlink()
        raise DownloadError(
            f"{path.name}: sha256 {digest} does not match pinned {pin.sha256}; "
            "deleted the file, rerun to fetch it again"
        )
    else:
        log.info("%s: size and sha256 verified", path.name)
    return digest


def fetch(pin: Pin, dest_dir: Path, force: bool = False) -> Path:
    """Download `pin.url` into `dest_dir` via a temp file; skip when already present."""
    if urlparse(pin.url).scheme != "https":
        raise DownloadError(f"refusing non-https URL: {pin.url}")
    target = dest_dir / pin.filename
    if target.is_file() and not force:
        log.info("%s already present, skipping download", target)
        return target
    log.info("downloading %s", pin.url)
    temp = temp_beside(target, ".part")
    opener = urllib.request.build_opener(HttpsOnlyRedirectHandler)
    try:
        with opener.open(pin.url, timeout=TIMEOUT_SECONDS) as response, temp.open("wb") as out:
            for chunk in iter(lambda: response.read(_CHUNK), b""):
                out.write(chunk)
        publish(temp, target)
    except BaseException:
        temp.unlink(missing_ok=True)
        raise
    return target


def is_safe_member(name: str) -> bool:
    """Reject absolute paths, drive letters, backslashes and any '..' component."""
    if not name or "\\" in name or name.startswith("/") or ":" in name.split("/", 1)[0]:
        return False
    return all(part not in ("..", "") for part in PurePosixPath(name).parts)


def safe_extract(zip_path: Path, dest_dir: Path) -> Path:
    """Extract every member of `zip_path` under `dest_dir`, guarding against traversal."""
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    resolved_dest = dest_dir.resolve()
    with zipfile.ZipFile(zip_path) as archive:
        members = archive.infolist()
        total = sum(member.file_size for member in members)
        if total > MAX_EXTRACT_BYTES:
            raise DownloadError(
                f"{zip_path.name}: refusing to extract {total} bytes (limit {MAX_EXTRACT_BYTES})"
            )
        for member in members:
            if not is_safe_member(member.filename):
                raise DownloadError(f"{zip_path.name}: unsafe zip member {member.filename!r}")
            final = (resolved_dest / member.filename).resolve()
            if resolved_dest != final and resolved_dest not in final.parents:
                raise DownloadError(
                    f"{zip_path.name}: member escapes destination: {member.filename!r}"
                )
            archive.extract(member, dest_dir)
    log.info("extracted %s to %s", zip_path.name, dest_dir)
    return dest_dir


def download_all(dest: Path, pins: dict[str, Pin], force: bool = False) -> dict[str, Path]:
    """Fetch, verify and unzip every pin into dest/<zip stem>/. Returns extraction dirs."""
    dest = Path(dest)
    extracted: dict[str, Path] = {}
    for key, pin in pins.items():
        zip_path = fetch(pin, dest, force=force)
        verify(zip_path, pin)
        extracted[key] = safe_extract(zip_path, dest / Path(pin.filename).stem)
    return extracted

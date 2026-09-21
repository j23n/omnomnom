"""Command line entry point: python3 -m fooddb {download,build}."""

from __future__ import annotations

import argparse
import logging
import sys
from collections.abc import Sequence
from pathlib import Path

from . import download as dl
from .build import DEFAULT_POPULAR, assemble
from .errors import FooddbError
from .fdc import find_bundles
from .output import write_sources_json, write_sqlite

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT = REPO_ROOT / "Omnomnom" / "Resources" / "foods.sqlite"
DEFAULT_SOURCES_OUT = REPO_ROOT / "Omnomnom" / "Resources" / "sources.json"
DEFAULT_DOWNLOADS = Path(__file__).resolve().parents[1] / "downloads"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fooddb", description="Build the bundled food database from USDA FoodData Central."
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    commands = parser.add_subparsers(dest="command", required=True)

    fetch = commands.add_parser("download", help="fetch and unzip the pinned FDC bundles")
    fetch.add_argument(
        "--dest", type=Path, default=DEFAULT_DOWNLOADS,
        help=f"download directory (default {DEFAULT_DOWNLOADS})",
    )
    fetch.add_argument("--foundation-url", default=dl.DEFAULT_FOUNDATION_URL)
    fetch.add_argument("--sr-legacy-url", default=dl.DEFAULT_SR_LEGACY_URL)
    fetch.add_argument("--force", action="store_true", help="re-download even if the zip exists")

    build = commands.add_parser(
        "build", help="build foods.sqlite and sources.json from unzipped bundles"
    )
    build.add_argument(
        "--fdc", type=Path, required=True, help="directory holding the unzipped FDC bundles"
    )
    build.add_argument(
        "--out", type=Path, default=DEFAULT_OUT, help=f"sqlite output (default {DEFAULT_OUT})"
    )
    build.add_argument(
        "--sources-out", type=Path, default=DEFAULT_SOURCES_OUT,
        help=f"manifest output (default {DEFAULT_SOURCES_OUT})",
    )
    build.add_argument(
        "--popular", type=Path, default=DEFAULT_POPULAR,
        help="curated popular descriptions file (default fooddb/curated/popular.txt)",
    )
    return parser


def run_download(args: argparse.Namespace) -> int:
    pins = {
        "foundation": _pin_for(args.foundation_url, dl.PINS["foundation"]),
        "sr_legacy": _pin_for(args.sr_legacy_url, dl.PINS["sr_legacy"]),
    }
    extracted = dl.download_all(args.dest, pins, force=args.force)
    for key, path in extracted.items():
        print(f"{key}: {path}")
    print(f"Next: python3 -m fooddb build --fdc {args.dest}")
    return 0


def _pin_for(url: str, default: dl.Pin) -> dl.Pin:
    """Keep pinned size/hash only when the URL is the pinned one."""
    return default if url == default.url else dl.Pin(url)


def run_build(args: argparse.Namespace) -> int:
    bundles = find_bundles(args.fdc)
    rows, summary = assemble(bundles, args.popular)
    versions = {bundle.source: bundle.version for bundle in bundles}
    meta = {f"{source}_version": version for source, version in versions.items()}
    write_sqlite(args.out, rows, meta)
    write_sources_json(args.sources_out, versions)
    print(summary.format())
    print(f"  wrote {args.out}\n  wrote {args.sources_out}")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    try:
        if args.command == "download":
            return run_download(args)
        return run_build(args)
    except FooddbError as error:
        logging.getLogger("fooddb").error("%s", error)
        return 1


if __name__ == "__main__":
    sys.exit(main())

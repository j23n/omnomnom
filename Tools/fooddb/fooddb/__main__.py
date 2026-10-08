"""Command line entry point: python3 -m fooddb {download,build,inspect}."""

from __future__ import annotations

import argparse
import logging
import sys
from collections.abc import Sequence
from pathlib import Path

from . import bls, ciqual
from . import download as dl
from .build import DEFAULT_POPULAR, assemble
from .bundles import Bundle
from .errors import FooddbError, InputError
from .fdc import find_bundles
from .inspection import describe
from .output import write_sources_json, write_sqlite

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT = REPO_ROOT / "Omnomnom" / "Resources" / "foods.sqlite"
DEFAULT_SOURCES_OUT = REPO_ROOT / "Omnomnom" / "Resources" / "sources.json"
DEFAULT_DOWNLOADS = Path(__file__).resolve().parents[1] / "downloads"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fooddb", description="Build the bundled food database from published food tables."
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    commands = parser.add_subparsers(dest="command", required=True)

    fetch = commands.add_parser("download", help="fetch and unzip the pinned FDC bundles")
    fetch.add_argument(
        "--dest", type=Path, default=DEFAULT_DOWNLOADS,
        help=f"download directory (default {DEFAULT_DOWNLOADS})",
    )
    fetch.add_argument("--force", action="store_true", help="re-download even if the zip exists")

    build = commands.add_parser(
        "build", help="build foods.sqlite and sources.json from one or more sources"
    )
    build.add_argument("--ciqual", type=Path, help="directory holding the Ciqual XML export")
    build.add_argument("--bls", type=Path, help="directory or file holding the BLS table")
    build.add_argument("--bls-sheet", help="sheet to read when the BLS workbook has several")
    build.add_argument("--fdc", type=Path, help="directory holding the unzipped FDC bundles")
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

    look = commands.add_parser(
        "inspect", help="print what a downloaded source contains, without building"
    )
    look.add_argument("path", type=Path, help="the folder or file a source was unzipped into")
    look.add_argument("--sheet", help="sheet to read when a workbook has several")
    return parser


def run_download(args: argparse.Namespace) -> int:
    extracted = dl.download_all(args.dest, dl.PINS, force=args.force)
    for key, path in extracted.items():
        print(f"{key}: {path}")
    print(f"Next: python3 -m fooddb build --fdc {args.dest}")
    return 0


def collect_bundles(args: argparse.Namespace) -> list[Bundle]:
    """Locate every source the command line names, in the order rows are assembled.

    The order the sources are appended in below is also the order dedup keeps:
    the first source to claim a name wins. Only sources actually passed to the
    build appear.
    """
    bundles: list[Bundle] = []
    if args.ciqual is not None:
        bundles.append(ciqual.find_bundle(args.ciqual))
    if args.bls is not None:
        bundles.append(bls.find_bundle(args.bls, args.bls_sheet))
    if args.fdc is not None:
        bundles.extend(find_bundles(args.fdc))
    if not bundles:
        raise InputError(
            "name at least one source: --ciqual, --bls or --fdc "
            "(see Tools/fooddb/README.md for where to download each)"
        )
    return bundles


def run_build(args: argparse.Namespace) -> int:
    bundles = collect_bundles(args)
    rows, summary = assemble(bundles, args.popular)
    versions = {bundle.source: bundle.version for bundle in bundles}
    meta = {f"{source}_version": version for source, version in versions.items()}
    write_sqlite(args.out, rows, meta)
    write_sources_json(args.sources_out, versions)
    print(summary.format())
    print(f"  wrote {args.out}\n  wrote {args.sources_out}")
    return 0


def run_inspect(args: argparse.Namespace) -> int:
    print(describe(args.path, args.sheet))
    return 0


MINIMUM_PYTHON = (3, 9)


def main(argv: Sequence[str] | None = None) -> int:
    if sys.version_info < MINIMUM_PYTHON:
        wanted = ".".join(str(part) for part in MINIMUM_PYTHON)
        print(f"fooddb needs Python {wanted} or newer", file=sys.stderr)
        return 1
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    try:
        if args.command == "download":
            return run_download(args)
        if args.command == "inspect":
            return run_inspect(args)
        return run_build(args)
    except FooddbError as error:
        logging.getLogger("fooddb").error("%s", error)
        return 1


if __name__ == "__main__":
    sys.exit(main())

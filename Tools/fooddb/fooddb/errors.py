"""Exception types shared across the package."""


class FooddbError(Exception):
    """Base class for validation failures that should end the CLI with exit code 1."""


class MappingError(FooddbError):
    """A nutrient id is missing from nutrient.csv or has an unexpected unit."""


class InputError(FooddbError):
    """The FDC input directory is missing files or is ambiguous."""


class DownloadError(FooddbError):
    """A download failed or did not match its pinned size or hash."""

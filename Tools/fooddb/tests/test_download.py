import hashlib
import io
import tempfile
import unittest
import urllib.request
import zipfile
from http.client import HTTPMessage
from pathlib import Path
from unittest import mock

from fooddb import download as dl
from fooddb.errors import DownloadError


class ZipGuardTests(unittest.TestCase):
    def test_member_names(self) -> None:
        for bad in ("../x.csv", "a/../../x", "/etc/passwd", "C:/x", "a\\..\\b", "..", ""):
            self.assertFalse(dl.is_safe_member(bad), bad)
        for good in ("food.csv", "bundle/food.csv", "a/b/c.csv", "dir/"):
            self.assertTrue(dl.is_safe_member(good), good)

    def test_crafted_zip_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "evil.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("ok/food.csv", "fdc_id\n")
                archive.writestr("../escape.csv", "fdc_id\n")
            with self.assertRaisesRegex(DownloadError, "unsafe zip member"):
                dl.safe_extract(zip_path, Path(tmp) / "out")
            self.assertFalse((Path(tmp) / "escape.csv").exists())

    def test_good_zip_extracts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "good.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("bundle/food.csv", "fdc_id\n")
            out = dl.safe_extract(zip_path, Path(tmp) / "out")
            self.assertTrue((out / "bundle" / "food.csv").is_file())

    def test_oversized_zip_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / "big.zip"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("a.csv", "x" * 10)
                archive.writestr("b.csv", "x" * 10)
            with mock.patch.object(dl, "MAX_EXTRACT_BYTES", 19):
                with self.assertRaisesRegex(DownloadError, "refusing to extract 20 bytes"):
                    dl.safe_extract(zip_path, Path(tmp) / "out")
            self.assertFalse((Path(tmp) / "out" / "a.csv").exists())


class VerifyTests(unittest.TestCase):
    def test_hash_and_size(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.zip"
            path.write_bytes(b"hello")
            digest = hashlib.sha256(b"hello").hexdigest()
            with self.assertLogs("fooddb.download", level="WARNING") as logs:
                self.assertEqual(dl.verify(path, dl.Pin("https://x/f.zip")), digest)
            self.assertIn(f"size=5 sha256={digest}; paste both into PINS", logs.output[0])
            self.assertEqual(dl.verify(path, dl.Pin("https://x/f.zip", 5, digest.upper())), digest)
            self.assertTrue(path.exists())

    def test_mismatch_deletes_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "f.zip"
            path.write_bytes(b"hello")
            with self.assertRaisesRegex(DownloadError, "size 5 does not match pinned 6; deleted"):
                dl.verify(path, dl.Pin("https://x/f.zip", size=6))
            self.assertFalse(path.exists())
            path.write_bytes(b"hello")
            with self.assertRaisesRegex(DownloadError, "sha256 .* does not match .*; deleted"):
                dl.verify(path, dl.Pin("https://x/f.zip", sha256="0" * 64))
            self.assertFalse(path.exists())

    def test_non_https_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(DownloadError, "https"):
                dl.fetch(dl.Pin("http://fdc.nal.usda.gov/x.zip"), Path(tmp))

    def test_pin_filename(self) -> None:
        self.assertEqual(
            dl.PINS["foundation"].filename, "FoodData_Central_foundation_food_csv_2025-04-24.zip"
        )


class RedirectTests(unittest.TestCase):
    def redirect(self, newurl: str) -> urllib.request.Request | None:
        handler = dl.HttpsOnlyRedirectHandler()
        request = urllib.request.Request("https://fdc.nal.usda.gov/fdc-datasets/x.zip")
        return handler.redirect_request(request, io.BytesIO(), 302, "Found", HTTPMessage(), newurl)

    def test_https_redirect_followed(self) -> None:
        request = self.redirect("https://cdn.example.org/x.zip")
        assert request is not None
        self.assertEqual(request.full_url, "https://cdn.example.org/x.zip")

    def test_http_redirect_refused(self) -> None:
        with self.assertRaisesRegex(DownloadError, "non-https URL: http://"):
            self.redirect("http://fdc.nal.usda.gov/fdc-datasets/x.zip")

    def test_fetch_uses_timeout_and_handler(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            response = mock.MagicMock()
            response.__enter__.return_value.read.side_effect = [b"data", b""]
            opener = mock.MagicMock()
            opener.open.return_value = response
            with mock.patch.object(urllib.request, "build_opener", return_value=opener) as build:
                target = dl.fetch(dl.Pin("https://x/f.zip"), Path(tmp))
            build.assert_called_once_with(dl.HttpsOnlyRedirectHandler)
            opener.open.assert_called_once_with("https://x/f.zip", timeout=60)
            self.assertEqual(target.read_bytes(), b"data")


if __name__ == "__main__":
    unittest.main()

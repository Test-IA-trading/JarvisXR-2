"""Fetch the checksum-pinned llama.cpp iPhone framework used by JARVIS's local brain.

The official llama.cpp release ships `llama-<tag>-xcframework.zip` with an
`ios-arm64` (device) slice and a macOS slice, but no iOS simulator slice. JARVIS
therefore links the framework only for iPhoneOS builds (see project.yml); simulator
builds compile the brain's unavailable path. This tool downloads the pinned release
asset, verifies its size and SHA-256, and extracts only the device framework to
`ios/JarvisXR/Frameworks/ios-arm64/llama.framework`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE_TAG = "b12262"
ASSET_NAME = f"llama-{RELEASE_TAG}-xcframework.zip"
DOWNLOAD_URL = f"https://github.com/ggml-org/llama.cpp/releases/download/{RELEASE_TAG}/{ASSET_NAME}"
EXPECTED_SIZE = 65_454_932
EXPECTED_SHA256 = "704a9ede82cfa161dfcb4971394ffcf61e4c4d0f3ca7ad17355a93a0f9d7718b"
SLICE_PREFIX = "build-apple/llama.xcframework/ios-arm64/llama.framework/"
DEFAULT_OUTPUT = ROOT / "ios" / "JarvisXR" / "Frameworks"
REQUIRED_MEMBERS = ("llama", "Info.plist", "Modules/module.modulemap", "Headers/llama.h")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_archive(path: Path) -> list[str]:
    failures: list[str] = []
    if not path.is_file():
        return [f"archive is missing: {path}"]
    size = path.stat().st_size
    if size != EXPECTED_SIZE:
        failures.append(f"archive size {size} != pinned {EXPECTED_SIZE}")
    digest = sha256_file(path)
    if digest != EXPECTED_SHA256:
        failures.append(f"archive SHA-256 {digest} != pinned {EXPECTED_SHA256}")
    return failures


def framework_is_complete(framework: Path) -> bool:
    return all((framework / member).is_file() and (framework / member).stat().st_size > 0 for member in REQUIRED_MEMBERS)


def extract_device_framework(archive_path: Path, output_root: Path) -> Path:
    destination = output_root / "ios-arm64" / "llama.framework"
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    with zipfile.ZipFile(archive_path) as archive:
        members = [info for info in archive.infolist() if info.filename.startswith(SLICE_PREFIX)]
        if not members:
            raise RuntimeError(f"{ASSET_NAME} has no {SLICE_PREFIX} slice")
        for info in members:
            relative = info.filename[len(SLICE_PREFIX):]
            if not relative or relative.endswith("/"):
                continue
            if relative.startswith("/") or ".." in Path(relative).parts:
                raise RuntimeError(f"unsafe archive member: {info.filename}")
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)
            mode = (info.external_attr >> 16) & 0o777
            os.chmod(target, mode or 0o644)
    if not framework_is_complete(destination):
        raise RuntimeError(f"extracted framework is incomplete: {destination}")
    return destination


def fetch(output_root: Path, cache_dir: Path | None, timeout: float) -> dict:
    framework = output_root / "ios-arm64" / "llama.framework"
    marker = output_root / "llama-framework.json"
    if framework_is_complete(framework) and marker.is_file():
        recorded = json.loads(marker.read_text(encoding="utf-8"))
        if recorded.get("sha256") == EXPECTED_SHA256:
            return {"status": "already_present", **recorded}

    cache_dir = cache_dir or Path(tempfile.gettempdir())
    cache_dir.mkdir(parents=True, exist_ok=True)
    archive_path = cache_dir / ASSET_NAME
    if not archive_path.is_file() or verify_archive(archive_path):
        request = urllib.request.Request(DOWNLOAD_URL, headers={"User-Agent": "JarvisXR-framework-fetch/1.0"})
        partial = archive_path.with_suffix(".download")
        with urllib.request.urlopen(request, timeout=timeout) as response, partial.open("wb") as sink:
            shutil.copyfileobj(response, sink, length=4 * 1024 * 1024)
        partial.replace(archive_path)
    failures = verify_archive(archive_path)
    if failures:
        archive_path.unlink(missing_ok=True)
        raise RuntimeError("llama.cpp framework verification failed: " + "; ".join(failures))

    extract_device_framework(archive_path, output_root)
    payload = {
        "release_tag": RELEASE_TAG,
        "asset": ASSET_NAME,
        "download_url": DOWNLOAD_URL,
        "sha256": EXPECTED_SHA256,
        "size_bytes": EXPECTED_SIZE,
        "slice": "ios-arm64",
        "license": "MIT (llama.cpp / ggml authors)",
    }
    marker.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {"status": "fetched", **payload}


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch and verify the pinned llama.cpp iPhone framework.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Directory that receives ios-arm64/llama.framework")
    parser.add_argument("--cache-dir", type=Path, help="Where to keep the downloaded archive")
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--report", type=Path, help="Optional JSON report path")
    args = parser.parse_args()
    result = fetch(args.output, args.cache_dir, args.timeout)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

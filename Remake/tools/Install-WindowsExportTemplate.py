#!/usr/bin/env python3
"""Install only Godot's Windows x86_64 templates from the official remote TPZ.

Godot 4.7's template manager reads the remote ZIP central directory and uses
HTTP Range requests for selected files.  This script mirrors that behavior so
CI/developer setup does not need the 1.2 GiB all-platform archive.
"""

from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile


DEFAULT_URL = (
    "https://godot-releases.nbg1.your-objectstorage.com/4.7.1-stable/"
    "Godot_v4.7.1-stable_export_templates.tpz"
)
EXPECTED_LENGTH = 1_280_486_955
BLOCK_SIZE = 4 * 1024 * 1024


class HttpRangeReader(io.RawIOBase):
    def __init__(self, url: str, expected_length: int = 0) -> None:
        self.url = url
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=45) as response:
            self.length = int(response.headers["Content-Length"])
            self.accept_ranges = response.headers.get("Accept-Ranges", "").lower()
        if expected_length and self.length != expected_length:
            raise RuntimeError(
                f"Unexpected remote archive length: {self.length}; "
                f"expected {expected_length}"
            )
        if self.accept_ranges != "bytes":
            raise RuntimeError("Official template mirror does not support byte ranges")
        self.position = 0
        self.cache: dict[int, bytes] = {}
        self.cache_order: list[int] = []
        self.downloaded_bytes = 0

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            target = offset
        elif whence == io.SEEK_CUR:
            target = self.position + offset
        elif whence == io.SEEK_END:
            target = self.length + offset
        else:
            raise ValueError(f"Unsupported seek mode: {whence}")
        if target < 0:
            raise ValueError("Negative seek position")
        self.position = min(target, self.length)
        return self.position

    def _get_block(self, block_index: int) -> bytes:
        cached = self.cache.get(block_index)
        if cached is not None:
            return cached
        start = block_index * BLOCK_SIZE
        end = min(start + BLOCK_SIZE, self.length) - 1
        request = urllib.request.Request(
            self.url,
            headers={"Range": f"bytes={start}-{end}", "User-Agent": "1937-Remake-Build"},
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206:
                raise RuntimeError(
                    f"Range request returned HTTP {response.status} for {start}-{end}"
                )
            data = response.read()
        expected = end - start + 1
        if len(data) != expected:
            raise RuntimeError(
                f"Short range response for {start}-{end}: {len(data)} bytes"
            )
        self.downloaded_bytes += len(data)
        self.cache[block_index] = data
        self.cache_order.append(block_index)
        while len(self.cache_order) > 4:
            oldest = self.cache_order.pop(0)
            self.cache.pop(oldest, None)
        return data

    def read(self, size: int = -1) -> bytes:
        if self.position >= self.length:
            return b""
        if size is None or size < 0:
            size = self.length - self.position
        size = min(size, self.length - self.position)
        remaining = size
        chunks: list[bytes] = []
        while remaining:
            block_index = self.position // BLOCK_SIZE
            block_offset = self.position % BLOCK_SIZE
            block = self._get_block(block_index)
            count = min(remaining, len(block) - block_offset)
            chunks.append(block[block_offset : block_offset + count])
            self.position += count
            remaining -= count
        return b"".join(chunks)


def requested_entries(names: list[str]) -> list[str]:
    normalized = {name.replace("\\", "/"): name for name in names}
    required_basenames = {
        "windows_release_x86_64.exe",
        "windows_debug_x86_64.exe",
        "version.txt",
    }
    selected: list[str] = []
    for normalized_name, original_name in normalized.items():
        basename = normalized_name.rsplit("/", 1)[-1]
        lower = basename.lower()
        if basename in required_basenames or (
            ("icu" in lower or "unicode" in lower)
            and not normalized_name.endswith("/")
        ):
            selected.append(original_name)
    missing = required_basenames.difference(
        {name.replace("\\", "/").rsplit("/", 1)[-1] for name in selected}
    )
    if missing:
        raise RuntimeError(f"Remote template archive is missing: {sorted(missing)}")
    return sorted(selected)


def install(url: str, destination: Path, list_only: bool) -> int:
    reader = HttpRangeReader(url, EXPECTED_LENGTH)
    with zipfile.ZipFile(reader) as archive:
        names = archive.namelist()
        selected = requested_entries(names)
        for name in selected:
            info = archive.getinfo(name)
            print(
                f"{name} ({info.file_size / 1024 / 1024:.1f} MiB, "
                f"compressed {info.compress_size / 1024 / 1024:.1f} MiB)"
            )
        if list_only:
            print(f"Remote bytes read: {reader.downloaded_bytes}")
            return 0
        destination.mkdir(parents=True, exist_ok=True)
        for name in selected:
            output = destination / Path(name.replace("\\", "/")).name
            temporary = output.with_suffix(output.suffix + ".partial")
            with archive.open(name) as source, temporary.open("wb") as target:
                shutil.copyfileobj(source, target, length=1024 * 1024)
            os.replace(temporary, output)
            print(f"Installed {output}")
    print(f"Remote bytes read: {reader.downloaded_bytes}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument(
        "--destination",
        default=str(
            Path(os.environ["APPDATA"])
            / "Godot"
            / "export_templates"
            / "4.7.1.stable"
        ),
    )
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()
    return install(args.url, Path(args.destination).resolve(), args.list_only)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # deliberate CLI boundary
        print(f"Template installation failed: {error}", file=sys.stderr)
        raise SystemExit(1)

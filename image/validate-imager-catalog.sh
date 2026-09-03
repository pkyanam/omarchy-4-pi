#!/bin/bash

# Fail closed when a generated Raspberry Pi Imager catalog cannot expose the
# Omarchy image through Imager 2.x's device-first selection flow.

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 CATALOG.json" >&2
  exit 64
fi

readonly catalog=$1

[[ -f $catalog ]] || { echo "Catalog not found: $catalog" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

python3 - "$catalog" <<'PY'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def fail(message: str) -> None:
    raise SystemExit(f"Invalid Raspberry Pi Imager catalog: {message}")


path = Path(sys.argv[1])
try:
    catalog = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
    fail(f"cannot read valid UTF-8 JSON from {path}: {error}")

if not isinstance(catalog, dict):
    fail("the root must be an object")

imager = catalog.get("imager")
if not isinstance(imager, dict):
    fail("top-level imager metadata is required for Imager 2.x")

devices = imager.get("devices")
if not isinstance(devices, list) or not devices:
    fail("imager.devices must contain at least one selectable device")

device_tags: set[str] = set()
pi4_device_found = False
for index, device in enumerate(devices):
    if not isinstance(device, dict):
        fail(f"imager.devices[{index}] must be an object")
    name = device.get("name")
    description = device.get("description")
    tags = device.get("tags")
    if not isinstance(name, str) or not name.strip():
        fail(f"imager.devices[{index}].name must be a non-empty string")
    if not isinstance(description, str) or not description.strip():
        fail(f"imager.devices[{index}].description must be a non-empty string")
    if not isinstance(tags, list) or not tags or not all(isinstance(tag, str) and tag for tag in tags):
        fail(f"imager.devices[{index}].tags must contain non-empty strings")
    device_tags.update(tags)
    if name == "Raspberry Pi 4" and "pi4-64bit" in tags:
        pi4_device_found = True

if not pi4_device_found:
    fail("a Raspberry Pi 4 device carrying the pi4-64bit tag is required")

os_list = catalog.get("os_list")
if not isinstance(os_list, list) or not os_list:
    fail("os_list must contain at least one image")

sha256_pattern = re.compile(r"[0-9a-f]{64}")
omarchy_pi4_found = False
for index, image in enumerate(os_list):
    if not isinstance(image, dict):
        fail(f"os_list[{index}] must be an object")
    name = image.get("name")
    image_tags = image.get("devices")
    if not isinstance(name, str) or not name.strip():
        fail(f"os_list[{index}].name must be a non-empty string")
    if not isinstance(image_tags, list) or not image_tags or not all(
        isinstance(tag, str) and tag for tag in image_tags
    ):
        fail(f"os_list[{index}].devices must contain non-empty strings")
    if not device_tags.intersection(image_tags):
        fail(f"os_list[{index}] is hidden because none of its device tags are selectable")
    if image.get("architecture") != "armv8":
        fail(f"os_list[{index}].architecture must be armv8")
    if image.get("init_format") != "rpi-preseed":
        fail(f"os_list[{index}].init_format must be rpi-preseed")
    for field in ("extract_size", "image_download_size"):
        value = image.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            fail(f"os_list[{index}].{field} must be a positive integer")
    for field in ("extract_sha256", "image_download_sha256"):
        value = image.get(field)
        if not isinstance(value, str) or not sha256_pattern.fullmatch(value):
            fail(f"os_list[{index}].{field} must be a lowercase SHA-256 digest")
    url = image.get("url")
    if not isinstance(url, str) or urlparse(url).scheme not in {"file", "http", "https"}:
        fail(f"os_list[{index}].url must be a file, HTTP, or HTTPS URL")
    if name == "Omarchy 4 Pi" and "pi4-64bit" in image_tags:
        omarchy_pi4_found = True

if not omarchy_pi4_found:
    fail("Omarchy 4 Pi must target pi4-64bit")

print(f"ok - {path.name} exposes Omarchy 4 Pi to a selectable Raspberry Pi 4")
PY

#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# > 1 )); then
    echo "Usage: $0 [output-directory]" >&2
    exit 2
fi
for tool in curl python3 exiftool; do
    command -v "$tool" >/dev/null || { echo "Required command: $tool" >&2; exit 1; }
done

output_dir=${1:-"$repo_dir/dist"}
mkdir -p -- "$output_dir"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

source_url=https://huggingface.co/datasets/AIDroneMap/aidm-vineyard-small/resolve/6af198c9a327e187e088ede6d7c632eb77b50eaa/aidm-vineyard-small-v1.zip
curl --fail --location --retry 3 --silent --show-error \
    --output "$work_dir/source.zip" "$source_url"

python3 - "$work_dir" "$output_dir" "$repo_dir/vineyard-ci-v1.sha256" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile
from decimal import Decimal

work, output, pinned_manifest = map(pathlib.Path, sys.argv[1:])
source_path = work / "source.zip"
expected_source = "db6feb86d55ab580782bf85193cc3e0393fe3f16aa36ec7b15f3d11a6456752f"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


if sha256(source_path) != expected_source:
    sys.exit("Source SHA-256 mismatch. No images were read.")

images = work / "images"
images.mkdir()
with zipfile.ZipFile(source_path) as source:
    entries = source.infolist()
    names = [entry.filename for entry in entries]
    if len(names) != 73 or len(set(names)) != 73:
        sys.exit("Expected 73 distinct source images.")
    if any(not re.fullmatch(r"[A-Za-z0-9_.-]+\.[Jj][Pp][Ee]?[Gg]", name) for name in names):
        sys.exit("Expected only JPEG images at the source archive root.")
    for name in names:
        (images / name).write_bytes(source.read(name))

    result = subprocess.run(
        ["exiftool", "-json", "-EXIF:DateTimeOriginal", "-EXIF:SubSecTimeOriginal", str(images)],
        check=True, capture_output=True, text=True,
    )
    metadata = json.loads(result.stdout)
    if len(metadata) != 73:
        sys.exit("Expected capture metadata for all 73 source images.")

    def capture_key(row):
        capture = datetime.datetime.strptime(row["DateTimeOriginal"], "%Y:%m:%d %H:%M:%S")
        subsecond = str(row.get("SubSecTimeOriginal", "0"))
        if not subsecond.isascii() or not subsecond.isdigit():
            sys.exit("Invalid EXIF SubSecTimeOriginal.")
        return capture, Decimal("0." + subsecond)

    capture_order = [pathlib.Path(row["SourceFile"]).name for row in sorted(metadata, key=capture_key)]
    filename_order = sorted(names)
    if sorted(capture_order) != filename_order:
        sys.exit("EXIF metadata does not cover the source files exactly once.")
    if capture_order != filename_order:
        print("Capture order:", *capture_order, sep="\n", file=sys.stderr)
        print("Filename order:", *filename_order, sep="\n", file=sys.stderr)
        sys.exit("Capture order differs from filename order. No output was published.")

    selected = capture_order[33:65]
    archive_name = "aidm-vineyard-ci-v1.zip"
    archive_path = work / archive_name
    checksums = []
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
        for name in sorted(selected):
            payload = source.read(name)
            if not payload.startswith(b"\xff\xd8\xff"):
                sys.exit("Invalid JPEG header: " + name)
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 0
            info.create_version = 20
            info.extract_version = 20
            info.compress_type = zipfile.ZIP_STORED
            info.internal_attr = 0
            info.extra = b""
            info.comment = b""
            archive.writestr(info, payload)
            # zipfile supplies permissions for zero attributes. Clear them before it writes the directory.
            info.external_attr = 0
            checksums.append(hashlib.sha256(payload).hexdigest() + "  " + name)

    with zipfile.ZipFile(archive_path) as archive:
        if archive.namelist() != sorted(selected) or archive.comment:
            sys.exit("Unexpected output archive entries or comment.")
        for info in archive.infolist():
            if (info.date_time != (1980, 1, 1, 0, 0, 0) or info.compress_type != zipfile.ZIP_STORED
                    or info.extra or info.comment or info.external_attr or info.internal_attr):
                sys.exit("Unexpected output archive metadata.")
            if archive.read(info) != source.read(info.filename):
                sys.exit("Output image differs from the source: " + info.filename)

archive_digest = sha256(archive_path)
checksums.append(archive_digest + "  " + archive_name)
manifest = "\n".join(checksums) + "\n"
if pinned_manifest.exists() and pinned_manifest.read_bytes() != manifest.encode("ascii"):
    sys.exit("Rebuilt checksums differ from vineyard-ci-v1.sha256. No output was published.")
shutil.copyfile(archive_path, output / archive_name)
(output / "vineyard-ci-v1.sha256").write_bytes(manifest.encode("ascii"))
print(archive_digest + "  " + archive_name)
print(str(archive_path.stat().st_size) + " bytes")
PY

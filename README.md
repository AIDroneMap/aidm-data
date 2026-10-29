# AIDroneMap test data

This repository pins drone image datasets for AIDroneMap tests. Images live only
in release assets. Git holds the rebuild script, checksums and documentation.

## Vineyard CI v1

`aidm-vineyard-ci-v1.zip` contains 32 images from `aidm-vineyard-small v1`.
They are positions 34 to 65 inclusive, counted from 1 in capture order. The
selection covers two full flight lines with their turns.

This set is for fast CI tests that check the code runs. It is not for accuracy
tests or benchmarks. Those use the full 73-image set.

The images keep their original names and bytes. There is no re-encoding,
resizing, or change to EXIF or XMP metadata.

- Release: <https://github.com/AIDroneMap/aidm-data/releases/tag/vineyard-ci-v1>
- Archive: <https://github.com/AIDroneMap/aidm-data/releases/download/vineyard-ci-v1/aidm-vineyard-ci-v1.zip>
- Size: 388,239,574 bytes
- SHA-256: `e9a0a6ffe425e878ba6417d28ce5aae8a64a653d3791195e848dff4539ec4156`
- First image: `DJI_20241224105147_0034_D.JPG`, capture position 34
- Last image: `DJI_20241224105220_0065_D.JPG`, capture position 65

`vineyard-ci-v1.sha256` records the SHA-256 of every selected image and the zip.
Release assets are immutable. A different selection or archive gets a new tag.

## Source pin

- Dataset: <https://huggingface.co/datasets/AIDroneMap/aidm-vineyard-small>
- Source tag: `v1`
- Commit: `6af198c9a327e187e088ede6d7c632eb77b50eaa`
- File: `aidm-vineyard-small-v1.zip`
- SHA-256: `db6feb86d55ab580782bf85193cc3e0393fe3f16aa36ec7b15f3d11a6456752f`
- Pinned download: <https://huggingface.co/datasets/AIDroneMap/aidm-vineyard-small/resolve/6af198c9a327e187e088ede6d7c632eb77b50eaa/aidm-vineyard-small-v1.zip>

## Rebuild

You need Bash, curl, Python 3 and ExifTool. On Debian or Ubuntu:

```sh
sudo apt-get install curl python3 libimage-exiftool-perl
```

Allow at least 3 GB of free disk space for the temporary source, extracted
images and output. The script uses `TMPDIR` for temporary files when set.

From a checkout of this repository, run:

```sh
bash -o pipefail scripts/make-vineyard-ci.sh
```

The script downloads the source at its commit pin and checks its SHA-256 before
reading images. It sorts all 73 images by EXIF `DateTimeOriginal`, then by
`SubSecTimeOriginal` as a decimal fraction. A missing subsecond field counts as
zero. All 73 source images have distinct `DateTimeOriginal` values and no
`SubSecTimeOriginal` field. Capture order matches filename order.

If the two orders differ, the script prints both and stops. Otherwise it takes
positions 34 to 65 and copies the image bytes into the zip. It sorts entries by
filename, stores them without compression, fixes timestamps at
`1980-01-01 00:00:00`, and writes no extra fields, comments or file attributes.
The archive contains the 32 JPEGs at its root and nothing else.

The script checks the output against the committed checksums and prints the
archive SHA-256 and byte size. It writes the zip and a copy of the checksum file
to `dist/`. To choose another output directory:

```sh
bash -o pipefail scripts/make-vineyard-ci.sh /path/to/output
```

Two separate builds from the pinned download produced the SHA-256 above. The
script enables `set -euo pipefail` and contains no pipelines.

To verify the zip and its extracted images together, place the checksum file
in their directory and run:

```sh
sha256sum --check vineyard-ci-v1.sha256
```

## Licence

The data uses [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), the same
licence as the source. [LICENSE](LICENSE) contains the full legal text from the
source pin.

Attribution: "AIDroneMap, provided by ITALDRONI".

This release selects 32 of the source's 73 images. The individual image files
are unchanged.

#!/usr/bin/env python3
"""Parse Android boot images (boot / init_boot / vendor_boot) with no external tools.

This is a read-only analyser. It never writes to a device and never executes
anything found inside an image.

The field layout follows AOSP's `system/tools/mkbootimg` (unpack_bootimg.py) and
`system/core/libbootimg`, i.e. the same definitions the bootloaders use:

  boot image, classic header (header_version 0-2)
      0   magic[8] "ANDROID!"
      8   kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
      24  second_size, second_addr, tags_addr, page_size, header_version
      44  os_version_patch_level
      48  product_name[16]
      64  cmdline[512]
      576 id[32]
      608 extra_cmdline[1024]
      1632 recovery_dtbo_size, recovery_dtbo_offset, boot_header_size (v1/v2)
      1648 dtb_size, dtb_load_address (v2)

  boot image, new header (header_version 3-4)
      0   magic[8] "ANDROID!"
      8   kernel_size, ramdisk_size, os_version_patch_level
      20  header_size
      24  reserved[16]
      40  header_version
      44  cmdline[1536]
      1580 boot_signature_size (v4)

  vendor boot image
      0   magic[8] "VNDRBOOT"
      8   header_version, page_size, kernel_addr, ramdisk_addr, vendor_ramdisk_size
      28  cmdline[2048]
      2076 tags_addr
      2080 product_name[16]
      2096 header_size, dtb_size, dtb_load_address

Usage:
    bootimg.py info    <image> [image...]
    bootimg.py extract <image> <outdir> [--dtb-only]
    bootimg.py dts     <image>            # print model/compatible of an embedded DTB
"""

from __future__ import annotations

import hashlib
import json
import os
import struct
import sys

BOOT_MAGIC = b"ANDROID!"
VENDOR_MAGIC = b"VNDRBOOT"
DTB_MAGIC = b"\xd0\x0d\xfe\xed"
V3_PAGE_SIZE = 4096


def _u32(buf: bytes, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


def _u64(buf: bytes, off: int) -> int:
    return struct.unpack_from("<Q", buf, off)[0]


def _cstr(buf: bytes, off: int, size: int) -> str:
    raw = buf[off: off + size]
    return raw.split(b"\x00", 1)[0].decode("utf-8", "replace").strip()


def page_size_of(value: int) -> int:
    """Android page sizes are powers of two in [2048, 65536]."""
    if value in (0, 1):
        return 2048
    if value < 2048 or value > 65536 or (value & (value - 1)) != 0:
        return 2048
    return value


def _num_pages(size: int, page: int) -> int:
    return (size + page - 1) // page


def _decode_os_version(raw: int) -> str:
    """AOSP packs os_version/os_patch_level into one 32-bit field."""
    if not raw:
        return ""
    os_version = raw >> 11
    a = os_version >> 14
    b = (os_version >> 7) & 0x7F
    c = os_version & 0x7F
    return "%d.%d.%d" % (a, b, c)


def parse(path: str) -> dict:
    with open(path, "rb") as fh:
        head = fh.read(4096)

    info: dict = {"file": os.path.basename(path), "path": path, "warnings": []}

    magic = head[:8]
    if magic == VENDOR_MAGIC:
        return _parse_vendor_boot(head, info)
    if magic != BOOT_MAGIC:
        info["type"] = "unknown"
        info["warnings"].append("missing ANDROID!/VNDRBOOT magic; not a boot image")
        info["size"] = os.path.getsize(path)
        return info

    info["type"] = "boot"
    header_version = _u32(head, 40)

    if header_version >= 3:
        # New (64-bit) header.
        info["header_version"] = header_version
        info["page_size"] = V3_PAGE_SIZE
        info["kernel_size"] = _u32(head, 8)
        info["ramdisk_size"] = _u32(head, 12)
        info["os_version"] = _decode_os_version(_u32(head, 16))
        info["os_patch_level"] = _u32(head, 16) & 0x7FF
        info["header_size"] = _u32(head, 20)
        info["cmdline"] = _cstr(head, 44, 1536)
        if header_version >= 4:
            info["boot_signature_size"] = _u32(head, 1580)
    else:
        # Classic header.
        info["header_version"] = header_version
        info["kernel_size"] = _u32(head, 8)
        info["kernel_addr"] = hex(_u32(head, 12))
        info["ramdisk_size"] = _u32(head, 16)
        info["ramdisk_addr"] = hex(_u32(head, 20))
        info["second_size"] = _u32(head, 24)
        info["second_addr"] = hex(_u32(head, 28))
        info["tags_addr"] = hex(_u32(head, 32))
        info["page_size"] = page_size_of(_u32(head, 36))
        info["os_version"] = _decode_os_version(_u32(head, 44))
        info["os_patch_level"] = _u32(head, 44) & 0x7FF
        info["name"] = _cstr(head, 48, 16)
        info["cmdline"] = _cstr(head, 64, 512)
        info["id"] = head[576:608].hex()
        extra = _cstr(head, 608, 1024)
        if extra:
            info["cmdline"] = (info["cmdline"] + " " + extra).strip()
        if header_version in (1, 2):
            info["recovery_dtbo_size"] = _u32(head, 1632)
            info["recovery_dtbo_offset"] = hex(_u64(head, 1636))
            info["boot_header_size"] = _u32(head, 1644)
        if header_version == 2:
            info["dt_size"] = _u32(head, 1648)
            info["dtb_addr"] = hex(_u64(head, 1652))
    return info


def _parse_vendor_boot(head: bytes, info: dict) -> dict:
    info["type"] = "vendor_boot"
    info["header_version"] = _u32(head, 8)
    info["page_size"] = page_size_of(_u32(head, 12))
    info["kernel_addr"] = hex(_u32(head, 16))
    info["ramdisk_addr"] = hex(_u32(head, 20))
    info["vendor_ramdisk_size"] = _u32(head, 24)
    info["cmdline"] = _cstr(head, 28, 2048)
    info["tags_addr"] = hex(_u32(head, 2076))
    info["name"] = _cstr(head, 2080, 16)
    info["header_size"] = _u32(head, 2096)
    info["dt_size"] = _u32(head, 2100)
    info["dtb_addr"] = hex(_u64(head, 2104))
    if info["header_version"] > 3:
        info["vendor_ramdisk_table_size"] = _u32(head, 2112)
        info["vendor_ramdisk_table_entry_num"] = _u32(head, 2116)
        info["vendor_ramdisk_table_entry_size"] = _u32(head, 2120)
        info["vendor_bootconfig_size"] = _u32(head, 2124)
    return info


def regions(info: dict, fh=None) -> list:
    """Return [(name, offset, size)] for the payload sections of the image.

    Offsets follow AOSP: the header always occupies one page, the kernel comes
    first, then the ramdisk, then second/recovery_dtbo/dtb.
    """
    if info.get("type") == "unknown":
        return []
    page = info.get("page_size") or 2048
    out = []

    if info["type"] == "vendor_boot":
        header_pages = _num_pages(info.get("header_size") or 2112, page)
        ramdisk_pages = _num_pages(info.get("vendor_ramdisk_size", 0), page)
        dtb_pages = _num_pages(info.get("dt_size", 0), page)
        base = page * header_pages
        if info.get("header_version", 0) > 3 and fh is not None:
            # v4 splits the vendor ramdisk into fragments described by a table.
            table_size = info.get("vendor_ramdisk_table_size", 0)
            entry_num = info.get("vendor_ramdisk_table_entry_num", 0)
            entry_size = info.get("vendor_ramdisk_table_entry_size", 0)
            # The table sits after the header, the vendor ramdisk and the DTB.
            table_offset = page * (header_pages + ramdisk_pages + dtb_pages)
            for i in range(entry_num):
                fh.seek(table_offset + entry_size * i)
                head = fh.read(12)
                if len(head) < 12:
                    break
                rsize, roff = struct.unpack_from("<II", head, 0)
                out.append(("vendor_ramdisk%02d" % i, base + roff, rsize))
            bootconfig_offset = page * (header_pages + ramdisk_pages + dtb_pages
                                        + _num_pages(table_size, page))
            out.append(("bootconfig", bootconfig_offset, info.get("vendor_bootconfig_size", 0)))
        else:
            out.append(("vendor_ramdisk", base, info.get("vendor_ramdisk_size", 0)))
        if info.get("dt_size"):
            out.append(("dtb", page * (header_pages + ramdisk_pages), info["dt_size"]))
        return out

    header_pages = 1
    kernel_pages = _num_pages(info.get("kernel_size", 0), page)
    ramdisk_pages = _num_pages(info.get("ramdisk_size", 0), page)
    out.append(("kernel", page * header_pages, info.get("kernel_size", 0)))
    out.append(("ramdisk", page * (header_pages + kernel_pages), info.get("ramdisk_size", 0)))
    if info.get("second_size"):
        out.append(("second", page * (header_pages + kernel_pages + ramdisk_pages),
                    info["second_size"]))
    if info.get("dt_size"):
        dtb_pages = _num_pages(info.get("second_size", 0), page)
        out.append(("dtb", page * (header_pages + kernel_pages + ramdisk_pages + dtb_pages),
                    info["dt_size"]))
    return out


def _read_at(fh, offset: int, size: int) -> bytes:
    if size <= 0:
        return b""
    fh.seek(offset)
    return fh.read(size)


def extract(path: str, outdir: str, dtb_only: bool = False) -> dict:
    info = parse(path)
    if info["type"] == "unknown":
        raise SystemExit("%s: not a boot image" % path)
    os.makedirs(outdir, exist_ok=True)
    base = os.path.splitext(os.path.basename(path))[0]
    written = []
    with open(path, "rb") as fh:
        for name, offset, size in regions(info, fh):
            if not size:
                continue
            if dtb_only and name != "dtb":
                continue
            data = _read_at(fh, offset, size)
            if len(data) < size:
                info["warnings"].append(
                    "truncated %s: wanted %d bytes, got %d" % (name, size, len(data)))
                data = data.ljust(size, b"\x00")
            if name == "dtb" and not data.startswith(DTB_MAGIC):
                info["warnings"].append("embedded DTB magic not found at offset %d" % offset)
            out = os.path.join(outdir, "%s.%s" % (base, name))
            with open(out, "wb") as oh:
                oh.write(data)
            written.append({"name": name, "file": out, "size": size, "offset": offset,
                            "sha256": hashlib.sha256(data).hexdigest()})
    info["extracted"] = written
    with open(os.path.join(outdir, base + ".info.json"), "w") as fh:
        json.dump(info, fh, indent=2)
    return info


def dtb_model(path: str) -> str:
    """Return the model/compatible string of an embedded DTB, if any."""
    info = parse(path)
    with open(path, "rb") as fh:
        for name, offset, size in regions(info):
            if name != "dtb" or not size:
                continue
            blob = _read_at(fh, offset, size)
            if not blob.startswith(DTB_MAGIC):
                return ""
            return _fdt_model(blob)
    return ""


def _fdt_model(blob: bytes) -> str:
    """Minimal FDT walk for /model and /compatible."""
    totalsize = struct.unpack_from(">I", blob, 4)[0]
    off = 40
    end = min(totalsize, len(blob))
    while off + 8 <= end:
        tag = struct.unpack_from(">I", blob, off)[0]
        if tag == 1:  # BEGIN_NODE
            off += 4
        elif tag == 2:  # END_NODE
            off += 4
        elif tag == 4:  # PROP
            length, nameoff = struct.unpack_from(">II", blob, off)
            off += 8
            value = blob[off: off + length]
            off += (length + 3) & ~3
            start = 40 + nameoff
            end_name = blob.find(b"\x00", start)
            pname = blob[start:end_name].decode("utf-8", "replace")
            if pname in ("model", "compatible"):
                return value.replace(b"\x00", b" ").decode("utf-8", "replace").strip()
        elif tag == 9:  # END
            break
        else:
            off += 4
    return ""


def fmt(info: dict) -> str:
    lines = ["## %s" % info.get("file", "?")]
    for key in ("type", "header_version", "page_size", "header_size", "kernel_size",
                "ramdisk_size", "vendor_ramdisk_size", "second_size", "dt_size",
                "os_version", "os_patch_level", "name", "id", "kernel_addr",
                "ramdisk_addr", "tags_addr", "dtb_addr", "boot_signature_size"):
        if key in info and info[key] not in ("", None):
            lines.append("- %s: %s" % (key, info[key]))
    if info.get("cmdline"):
        lines.append("- cmdline: %s" % info["cmdline"])
    for name, offset, size in regions(info):
        if size:
            lines.append("- %s: offset %d size %d" % (name, offset, size))
    for warn in info.get("warnings", []):
        lines.append("- WARNING: %s" % warn)
    return "\n".join(lines)


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "info":
        if len(argv) < 3:
            print("usage: bootimg.py info <image> [...]")
            return 2
        for path in argv[2:]:
            print(fmt(parse(path)))
        return 0
    if cmd == "extract":
        if len(argv) < 4:
            print("usage: bootimg.py extract <image> <outdir> [--dtb-only]")
            return 2
        dtb_only = "--dtb-only" in argv[4:]
        out = extract(argv[2], argv[3], dtb_only)
        print(fmt(out))
        for item in out.get("extracted", []):
            print("- wrote %s (%d bytes, sha256 %s)" % (item["file"], item["size"], item["sha256"]))
        return 0
    if cmd == "dts":
        if len(argv) < 3:
            print("usage: bootimg.py dts <image>")
            return 2
        model = dtb_model(argv[2])
        print(model or "(no embedded DTB model found)")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

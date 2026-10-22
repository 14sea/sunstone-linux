#!/usr/bin/env python3
"""Minimal Android boot image v3/v4 packer (kernel + ramdisk, no DTB).

Layout per AOSP bootimg.h: one 4096-byte header page, then the kernel and
the ramdisk, each padded to 4096. v4 adds signature_size (0 here, no boot
signature). With v3/v4 the DTB comes from vendor_boot, so none is packed.
"""
import argparse
import struct

PAGE = 4096


def os_version(ver, patch):
    a, b, c = (int(x) for x in ver.split('.'))
    y, m = (int(x) for x in patch.split('-'))
    return ((a << 14) | (b << 7) | c) << 11 | ((y - 2000) << 4) | m


def pad(data):
    return data + b'\0' * (-len(data) % PAGE)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kernel', required=True)
    ap.add_argument('--ramdisk', required=True)
    ap.add_argument('--header-version', type=int, choices=(3, 4), default=3)
    ap.add_argument('--os-version', default='16.0.0')
    ap.add_argument('--os-patch-level', default='2026-09')
    ap.add_argument('--cmdline', default='')
    ap.add_argument('-o', '--output', required=True)
    a = ap.parse_args()

    kernel = open(a.kernel, 'rb').read()
    ramdisk = open(a.ramdisk, 'rb').read()
    cmdline = a.cmdline.encode()
    assert len(cmdline) < 1536

    hdr = b'ANDROID!'
    hdr += struct.pack('<4I', len(kernel), len(ramdisk),
                       os_version(a.os_version, a.os_patch_level),
                       1580 if a.header_version == 3 else 1584)
    hdr += struct.pack('<4I', 0, 0, 0, 0)          # reserved
    hdr += struct.pack('<I', a.header_version)
    hdr += cmdline.ljust(1536, b'\0')
    if a.header_version == 4:
        hdr += struct.pack('<I', 0)                # signature_size
    with open(a.output, 'wb') as f:
        f.write(pad(hdr) + pad(kernel) + pad(ramdisk))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Pack an arm64 Linux Image and a DTB into the SWEETLNX payload the shim boots (shim/loader.c).

  mklinuxpayload.py Image board.dtb OUT [--load 0x180000000] [--dtb-pa ADDR]

Layout: 72-byte header ("SWEETLNX", u32 version 1, u32 header size, u64 image_off, image_size,
dtb_off, dtb_size, load_pa, dtb_pa, payload_size), the Image at image_off, the DTB at dtb_off
(both 4K aligned). The shim copies the Image to load_pa + text_offset and the DTB to dtb_pa.
Default load_pa: the start of sunstone's upper DDR bank (0x1_80000000, free of carve-outs);
default dtb_pa: 2 MiB above the end of the kernel's memory footprint (Image header image_size).
"""
import argparse
import struct
import sys

HDR = struct.Struct('<8sII7Q')
ARM64_MAGIC = 0x644d5241
SZ_2M = 0x200000


def align(v, a):
    return (v + a - 1) & ~(a - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('dtb')
    ap.add_argument('out')
    ap.add_argument('--load', type=lambda s: int(s, 0), default=0x180000000)
    ap.add_argument('--dtb-pa', type=lambda s: int(s, 0))
    a = ap.parse_args()

    image = open(a.image, 'rb').read()
    dtb = open(a.dtb, 'rb').read()
    if len(image) < 64 or struct.unpack_from('<I', image, 0x38)[0] != ARM64_MAGIC:
        sys.exit(f'{a.image}: not an arm64 Image')
    if dtb[:4] != b'\xd0\x0d\xfe\xed':
        sys.exit(f'{a.dtb}: not a flattened device tree')
    if len(dtb) > SZ_2M:
        sys.exit(f'{a.dtb}: larger than 2 MiB')
    if a.load % SZ_2M:
        sys.exit('--load must be 2 MiB aligned')
    text_offset, ksize = struct.unpack_from('<QQ', image, 8)
    ksize = ksize or len(image)
    dtb_pa = a.dtb_pa if a.dtb_pa is not None else align(a.load + text_offset + ksize, SZ_2M) + SZ_2M
    if dtb_pa % 8:
        sys.exit('--dtb-pa must be 8-byte aligned')

    image_off = align(HDR.size, 0x1000)
    dtb_off = align(image_off + len(image), 0x1000)
    total = dtb_off + len(dtb)
    out = bytearray(total)
    HDR.pack_into(out, 0, b'SWEETLNX', 1, HDR.size, image_off, len(image), dtb_off, len(dtb),
                  a.load, dtb_pa, total)
    out[image_off:image_off + len(image)] = image
    out[dtb_off:dtb_off + len(dtb)] = dtb
    open(a.out, 'wb').write(out)
    print(f'{a.out}: {total} bytes; Image {len(image)} (memory {ksize:#x}, text_offset {text_offset:#x}) '
          f'-> {a.load + text_offset:#x}, DTB {len(dtb)} -> {dtb_pa:#x}')


if __name__ == '__main__':
    main()

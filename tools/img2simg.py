#!/usr/bin/env python3
"""Convert a raw (sparse-on-disk) image into an Android sparse image for fastboot.

  img2simg.py RAW OUT [--block 4096]

Data extents (SEEK_DATA/SEEK_HOLE) become RAW chunks; holes become FILL chunks of zeros, not
DONT_CARE, so the bootloader zeroes them and nothing of the partition's old contents shows
through inside the image's range.
"""
import argparse
import os
import struct

MAGIC = 0xed26ff3a
RAW, FILL = 0xcac1, 0xcac2
FILE_HDR = struct.Struct('<IHHHHIIII')
CHUNK_HDR = struct.Struct('<HHII')


def extents(fd, size):
    pos = 0
    while pos < size:
        try:
            data = os.lseek(fd, pos, os.SEEK_DATA)
        except OSError:
            data = size
        if data > pos:
            yield False, pos, data
        if data >= size:
            break
        hole = os.lseek(fd, data, os.SEEK_HOLE)
        yield True, data, hole
        pos = hole


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('raw')
    ap.add_argument('out')
    ap.add_argument('--block', type=int, default=4096)
    a = ap.parse_args()
    bs = a.block
    fd = os.open(a.raw, os.O_RDONLY)
    size = os.fstat(fd).st_size
    if size % bs:
        raise SystemExit('image size is not a multiple of the block size')

    # a block with any data in it is a data block; everything else is zero fill
    data = []
    for is_data, s, e in extents(fd, size):
        if not is_data:
            continue
        s, e = s // bs, -(-e // bs)
        if data and s <= data[-1][1]:
            data[-1][1] = max(data[-1][1], e)
        else:
            data.append([s, e])
    chunks, pos = [], 0
    for s, e in data:
        if s > pos:
            chunks.append((False, pos, s))
        chunks.append((True, s, e))
        pos = e
    if pos < size // bs:
        chunks.append((False, pos, size // bs))

    with open(a.out, 'wb') as out:
        out.write(FILE_HDR.pack(MAGIC, 1, 0, FILE_HDR.size, CHUNK_HDR.size, bs, size // bs, len(chunks), 0))
        for is_data, s, e in chunks:
            n = e - s
            if is_data:
                out.write(CHUNK_HDR.pack(RAW, 0, n, CHUNK_HDR.size + n * bs))
                os.lseek(fd, s * bs, os.SEEK_SET)
                left = n * bs
                while left:
                    buf = os.read(fd, min(left, 1 << 24))
                    out.write(buf)
                    left -= len(buf)
            else:
                out.write(CHUNK_HDR.pack(FILL, 0, n, CHUNK_HDR.size + 4))
                out.write(b'\0\0\0\0')
    data = sum(e - s for d, s, e in chunks if d)
    print(f'{a.out}: {len(chunks)} chunks, {data * bs >> 20} MiB data of {size >> 20} MiB')


if __name__ == '__main__':
    main()

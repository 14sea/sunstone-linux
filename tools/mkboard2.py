#!/usr/bin/env python3
"""Add a board data entry to an ath10k board-2.bin.

  mkboard2.py IN-board-2.bin BDF-FILE NAME OUT-board-2.bin

NAME is the ath10k board name to match, e.g.
  bus=snoc,qmi-board-id=ff,qmi-chip-id=150,variant=xiaomi_sunstone
(the variant comes from the DT property qcom,calibration-variant on the wifi node). Existing entries
are kept, an entry with the same name is replaced. Used with the phone's own bdwlan.* file, so no
vendor data lives in the repository; the result goes to /lib/firmware/updates/ath10k/WCN3990/hw1.0/.

Format (ath10k hw.h): "QCA-ATH10K-BOARD\\0", then 4-byte aligned IEs {u32 id, u32 len, data};
IE 0 = board: sub-IEs {u32 id, u32 len, data}, 0 = name, 1 = data.
"""
import struct
import sys

MAGIC = b'QCA-ATH10K-BOARD\0'
IE_BOARD, SUB_NAME, SUB_DATA = 0, 0, 1


def pad4(b):
    return b + b'\0' * (-len(b) % 4)


def ies(blob, start):
    p = start
    while p + 8 <= len(blob):
        ie_id, ie_len = struct.unpack_from('<II', blob, p)
        yield ie_id, blob[p + 8:p + 8 + ie_len]
        p += 8 + ie_len + (-ie_len % 4)


def board_name(body):
    for sid, val in ies(body, 0):
        if sid == SUB_NAME:
            return val.decode()
    return None


def main():
    src, bdf, name, out = sys.argv[1:5]
    blob = open(src, 'rb').read()
    if not blob.startswith(MAGIC):
        sys.exit(f'{src}: not an ath10k board-2.bin')
    data = open(bdf, 'rb').read()
    start = len(MAGIC) + (-len(MAGIC) % 4)
    kept = [(i, b) for i, b in ies(blob, start) if not (i == IE_BOARD and board_name(b) == name)]
    sub = b''.join(struct.pack('<II', sid, len(v)) + pad4(v)
                   for sid, v in ((SUB_NAME, name.encode()), (SUB_DATA, data)))
    kept.append((IE_BOARD, sub))
    res = pad4(MAGIC) + b''.join(struct.pack('<II', i, len(b)) + pad4(b) for i, b in kept)
    open(out, 'wb').write(res)
    print(f'{out}: {len(kept)} board entries, added "{name}" ({len(data)} bytes)')


if __name__ == '__main__':
    main()

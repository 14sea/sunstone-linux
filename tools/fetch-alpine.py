#!/usr/bin/env python3
"""Fetch prebuilt Alpine aarch64 packages for the initramfs and check them against APKINDEX.

  fetch-alpine.py PKG...      -> downloads/alpine/PKG-VER.apk, unpacked into downloads/alpine/PKG/

An .apk is three concatenated gzip streams: signature, control (.PKGINFO), data. APKINDEX's C:
field is "Q1" + base64(sha1(control stream)); .PKGINFO's datahash is sha256(data stream). Both are
checked, so every file is tied to the index. The index's own RSA signature is not verified.
"""
import base64
import hashlib
import io
import os
import sys
import tarfile
import urllib.request
import zlib

MIRROR = 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64/'
DL = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'downloads', 'alpine')


def index():
    pkgs = {}
    for rec in open(os.path.join(DL, 'APKINDEX')).read().split('\n\n'):
        f = dict(l.split(':', 1) for l in rec.splitlines() if len(l) > 2 and l[1] == ':')
        if 'P' in f:
            pkgs[f['P']] = f
    return pkgs


def gzip_streams(blob):
    out, pos = [], 0
    while pos < len(blob):
        d = zlib.decompressobj(31)
        d.decompress(blob[pos:])
        end = len(blob) - len(d.unused_data)
        out.append(blob[pos:end])
        pos = end
    return out


def main():
    idx = index()
    for name in sys.argv[1:]:
        f = idx[name]
        apk = os.path.join(DL, f'{name}-{f["V"]}.apk')
        if not os.path.exists(apk):
            urllib.request.urlretrieve(MIRROR + os.path.basename(apk), apk)
        blob = open(apk, 'rb').read()
        sig, ctl, data = gzip_streams(blob)
        if 'Q1' + base64.b64encode(hashlib.sha1(ctl).digest()).decode() != f['C']:
            sys.exit(f'{apk}: control checksum does not match APKINDEX')
        info = tarfile.open(fileobj=io.BytesIO(ctl)).extractfile('.PKGINFO').read().decode()
        want = dict(l.split(' = ', 1) for l in info.splitlines() if ' = ' in l)['datahash']
        if hashlib.sha256(data).hexdigest() != want:
            sys.exit(f'{apk}: data hash does not match .PKGINFO')
        dest = os.path.join(DL, name)
        os.makedirs(dest, exist_ok=True)
        tarfile.open(fileobj=io.BytesIO(data)).extractall(dest, filter='data')
        print(f'{name} {f["V"]}: ok -> downloads/alpine/{name}/')


if __name__ == '__main__':
    main()

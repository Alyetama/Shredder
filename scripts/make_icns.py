#!/usr/bin/env python3
"""Build an ICNS container from PNG icon representations."""
import struct
import sys
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
representations = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
chunks = []
for kind, name in representations:
    data = (source / name).read_bytes()
    chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
body = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)

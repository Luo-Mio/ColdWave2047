import zlib
import struct

def parse_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    idx = 8
    idat = bytearray()
    w, h = 0, 0
    while idx < len(data):
        length = struct.unpack(">I", data[idx:idx+4])[0]
        ctype = data[idx+4:idx+8]
        chunk = data[idx+8:idx+8+length]
        idx += 12 + length
        if ctype == b"IHDR":
            w, h = struct.unpack(">II", chunk[:8])
            bit_depth, color_type = chunk[8], chunk[9]
            assert color_type == 6 # RGBA
            assert bit_depth == 8
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    # Recon scanlines
    bpp = 4
    stride = w * bpp
    pixels = bytearray(w * h * bpp)
    raw_idx = 0
    for y in range(h):
        filter_type = raw[raw_idx]
        raw_idx += 1
        line = bytearray(raw[raw_idx:raw_idx+stride])
        raw_idx += stride
        if filter_type == 0:
            pass
        elif filter_type == 1: # Sub
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x-bpp]) & 0xFF
        elif filter_type == 2: # Up
            prior = pixels[(y-1)*stride : y*stride] if y > 0 else bytearray(stride)
            for x in range(stride):
                line[x] = (line[x] + prior[x]) & 0xFF
        elif filter_type == 3: # Average
            prior = pixels[(y-1)*stride : y*stride] if y > 0 else bytearray(stride)
            for x in range(stride):
                a = line[x-bpp] if x >= bpp else 0
                b = prior[x]
                line[x] = (line[x] + ((a + b) // 2)) & 0xFF
        elif filter_type == 4: # Paeth
            prior = pixels[(y-1)*stride : y*stride] if y > 0 else bytearray(stride)
            for x in range(stride):
                a = line[x-bpp] if x >= bpp else 0
                b = prior[x]
                c = prior[x-bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 0xFF
        pixels[y*stride : (y+1)*stride] = line
    return w, h, pixels

w, h, pixels = parse_png(r"d:\Project\Project-Godot\测试001\resources\surface\GreenGrass\grass_out.png")
print(f"Image: {w}x{h}")

def get_a(x, y):
    return pixels[(y * w + x) * 4 + 3]

for r in range(4):
    for c in range(4):
        x0 = c * 64
        y0 = r * 32
        # check 4 quadrants/corners inside 64x32
        top_a = get_a(x0 + 32, y0 + 6) > 100
        rt_a  = get_a(x0 + 52, y0 + 16) > 100
        bm_a  = get_a(x0 + 32, y0 + 26) > 100
        lt_a  = get_a(x0 + 12, y0 + 16) > 100
        mid_a = get_a(x0 + 32, y0 + 16) > 100
        print(f"Tile ({c}, {r}): mid={mid_a:1} | T={top_a:1}, R={rt_a:1}, B={bm_a:1}, L={lt_a:1}")


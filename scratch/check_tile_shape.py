from inspect_png import parse_png

w, h, pixels = parse_png(r"d:\Project\Project-Godot\测试001\resources\surface\GreenGrass\grass_out.png")

def get_a(x, y):
    return pixels[(y * w + x) * 4 + 3]

# Let's inspect Tile (0, 0) - top-left 64x32
print("Tile (0, 0) alpha map:")
for y in range(0, 32, 2):
    row_str = ""
    for x in range(0, 64, 2):
        row_str += "#" if get_a(x, y) > 100 else "."
    print(row_str)

print("\nTile (2, 1) alpha map (Full tile):")
for y in range(0, 32, 2):
    row_str = ""
    for x in range(128, 192, 2):
        row_str += "#" if get_a(x, y + 32) > 100 else "."
    print(row_str)


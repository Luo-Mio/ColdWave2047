import json
from PIL import Image, ImageDraw

with open('data/editor_map_dump.json', 'r') as f:
    work_dump = json.load(f)

def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

tiles = work_dump.get('tiles', [])
print(f"Total tiles in work_dump: {len(tiles)}")

# Let's inspect tiles by floor
floors = {}
for t in tiles:
    z = t.get('z', 0)
    floors[z] = floors.get(z, 0) + 1
print(f"Tiles by floor: {floors}")

# Let's check where the user drew floor 0 tiles around player (4, 28)
# Player is at (4, 28)
p_cx, p_cy = 4, 28
p_pos = cell_to_world(p_cx, p_cy)

# What are the min/max u, v of all tiles in work_dump relative to player?
f0_tiles = [t for t in tiles if t.get('z', 0) == 0]
uvs = []
for t in f0_tiles:
    wp = cell_to_world(t['x'], t['y'])
    rel_x = wp[0] - p_pos[0]
    rel_y = wp[1] - p_pos[1]
    u = (rel_x / 64.0) + (rel_y / 32.0)
    v = (rel_y / 32.0) - (rel_x / 64.0)
    uvs.append((t['x'], t['y'], u, v))

print(f"Relative to player (4, 28):")
print(f"u range: [{min(x[2] for x in uvs):.1f}, {max(x[2] for x in uvs):.1f}]")
print(f"v range: [{min(x[3] for x in uvs):.1f}, {max(x[3] for x in uvs):.1f}]")

# Let's check along the 4 diagonal directions:
# NW (u <= 0, v = 0)
# SE (u >= 0, v = 0)
# NE (v <= 0, u = 0)
# SW (v >= 0, u = 0)
for dir_name, cond in [
    ("NW (u <= 0, v = 0)", lambda u, v: abs(v) < 0.01 and u <= 0),
    ("SE (u >= 0, v = 0)", lambda u, v: abs(v) < 0.01 and u >= 0),
    ("NE (v <= 0, u = 0)", lambda u, v: abs(u) < 0.01 and v <= 0),
    ("SW (v >= 0, u = 0)", lambda u, v: abs(u) < 0.01 and v >= 0),
]:
    matching = [x for x in uvs if cond(x[2], x[3])]
    print(f"Direction {dir_name}: count = {len(matching)}")
    if matching:
        print(f"   min u = {min(x[2] for x in matching):.1f}, max u = {max(x[2] for x in matching):.1f}")
        print(f"   min v = {min(x[3] for x in matching):.1f}, max v = {max(x[3] for x in matching):.1f}")


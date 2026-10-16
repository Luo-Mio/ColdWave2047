import json

with open('data/editor_map_dump.json', 'r') as f:
    dump = json.load(f)

# Find tiles near player (4, 28)
p_x, p_y = 4, 28

# Let's see all tiles where z > 0
high = [t for t in dump['tiles'] if t['z'] > 0]
print(f"Total high tiles: {len(high)}")

# Group high tiles by cluster or coordinates:
for t in high:
    dx = t['x'] - p_x
    dy = t['y'] - p_y
    if abs(dx) < 15 and abs(dy) < 25:
        print(f"High tile: ({t['x']}, {t['y']}, z={t['z']}), rel to player: dx={dx}, dy={dy}")


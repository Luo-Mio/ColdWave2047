import json
from PIL import Image, ImageDraw

with open("scratch/template_cells.json", "r") as f:
    cells = json.load(f)

print(f"Total template cells: {len(cells)}")

def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

min_wx = min(cell_to_world(c[0], c[1])[0] for c in cells)
max_wx = max(cell_to_world(c[0], c[1])[0] for c in cells)
min_wy = min(cell_to_world(c[0], c[1])[1] for c in cells)
max_wy = max(cell_to_world(c[0], c[1])[1] for c in cells)

print(f"World bounds: X=[{min_wx}, {max_wx}], Y=[{min_wy}, {max_wy}]")

player_cell = [4, 28]
pw = cell_to_world(player_cell[0], player_cell[1])
print(f"Player cell: {player_cell}, world: {pw}")

# Check coverage around player cell:
# In each direction from player, how far do template cells go?
cell_set = set((c[0], c[1]) for c in cells)

for dir_name, (dcx, dcy) in [
    ("East (dx=+1, dy=0)", (1, 0)),
    ("West (dx=-1, dy=0)", (-1, 0)),
    ("South (dx=0, dy=+2)", (0, 2)),
    ("North (dx=0, dy=-2)", (0, -2)),
    ("Southeast", (0, 1)), # from even: (0, 1), then (1, 2)...
]:
    count = 0
    curr = list(player_cell)
    for step in range(1, 50):
        if dir_name == "Southeast":
            if curr[1] % 2 == 0:
                curr = [curr[0], curr[1] + 1]
            else:
                curr = [curr[0] + 1, curr[1] + 1]
        else:
            curr = [curr[0] + dcx, curr[1] + dcy]
        if tuple(curr) in cell_set:
            count += 1
        else:
            break
    print(f"Template cells in direction {dir_name}: {count} tiles")


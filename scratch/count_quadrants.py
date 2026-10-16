def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

center_cx, center_cy = 4, 27 # odd
c_pos = cell_to_world(center_cx, center_cy)

rendered_cells = []
for dy in range(-25, 26):
    for dx in range(-15, 16):
        cx = center_cx + dx
        cy = center_cy + dy
        wp = cell_to_world(cx, cy)
        rel_x = wp[0] - c_pos[0]
        rel_y = wp[1] - c_pos[1]
        u = (rel_x / 64.0) + (rel_y / 32.0)
        v = (rel_y / 32.0) - (rel_x / 64.0)
        if abs(u) <= limit and abs(v) <= limit:
            rendered_cells.append((dx, dy, rel_x, rel_y, u, v))

# Count in each quadrant by (dx, dy):
nw = [c for c in rendered_cells if c[0] < 0 and c[1] < 0]
ne = [c for c in rendered_cells if c[0] > 0 and c[1] < 0]
sw = [c for c in rendered_cells if c[0] < 0 and c[1] > 0]
se = [c for c in rendered_cells if c[0] > 0 and c[1] > 0]

print(f"Quadrant counts by (dx, dy) for odd center:")
print(f"  Northwest (dx < 0, dy < 0): {len(nw)}")
print(f"  Northeast (dx > 0, dy < 0): {len(ne)}")
print(f"  Southwest (dx < 0, dy > 0): {len(sw)}")
print(f"  Southeast (dx > 0, dy > 0): {len(se)}")


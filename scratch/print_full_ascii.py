def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

center_cx, center_cy = 4, 28
c_pos = cell_to_world(center_cx, center_cy)

rendered = set()
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
            rendered.add((dx, dy))

print("=== FULL ASCII GRID of (dx, dy) ===")
for dy in range(-18, 19):
    line = ""
    for dx in range(-10, 11):
        if dx == 0 and dy == 0:
            line += "O"
        elif (dx, dy) in rendered:
            line += "#"
        else:
            line += "."
    print(f"{dy:+3d}: {line}")


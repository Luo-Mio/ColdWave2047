def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

# Player is at (4, 27) (ODD row)
center_cx, center_cy = 4, 27
c_pos = cell_to_world(center_cx, center_cy)

rows = {}
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
            if rel_y not in rows:
                rows[rel_y] = []
            rows[rel_y].append((cx, cy, rel_x))

print("Total screen rows for odd center (4, 27):", len(rows))
sorted_y = sorted(rows.keys())
for ry in sorted_y:
    xs = sorted([t[2] for t in rows[ry]])
    min_x = min(xs)
    max_x = max(xs)
    print(f"rel_y = {ry:+6.0f} (dy={ry/16:+3.0f}) : count = {len(xs):2d}, rel_x range = [{min_x:+6.0f}, {max_x:+6.0f}], center_x = {(min_x+max_x)/2:+5.0f}")


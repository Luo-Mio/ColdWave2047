def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

center_cx, center_cy = 4, 28
c_pos = cell_to_world(center_cx, center_cy)

se_edge = []
for dy in range(-25, 26):
    for dx in range(-15, 16):
        cx = center_cx + dx
        cy = center_cy + dy
        wp = cell_to_world(cx, cy)
        rel_x = wp[0] - c_pos[0]
        rel_y = wp[1] - c_pos[1]
        u = (rel_x / 64.0) + (rel_y / 32.0)
        v = (rel_y / 32.0) - (rel_x / 64.0)
        if abs(u - 9.0) < 0.01:
            se_edge.append((cx, cy, dx, dy, rel_x, rel_y, round(u), round(v)))

print("Tiles on SE edge (u = 9):")
for t in sorted(se_edge, key=lambda x: x[3]):
    print(f"  cell ({t[0]}, {t[1]}), dx={t[2]:+2d}, dy={t[3]:+2d}, v={t[7]:+2d}, rel=({t[4]:+6.0f}, {t[5]:+6.0f})")


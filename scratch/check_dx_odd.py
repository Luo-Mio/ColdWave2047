def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

center_cx, center_cy = 4, 27 # odd
c_pos = cell_to_world(center_cx, center_cy)

print("For odd center_cy = 27:")
for dy in range(-18, 19):
    dxs = []
    for dx in range(-20, 21):
        cx = center_cx + dx
        cy = center_cy + dy
        wp = cell_to_world(cx, cy)
        rel_x = wp[0] - c_pos[0]
        rel_y = wp[1] - c_pos[1]
        u = (rel_x / 64.0) + (rel_y / 32.0)
        v = (rel_y / 32.0) - (rel_x / 64.0)
        if abs(u) <= limit and abs(v) <= limit:
            dxs.append(dx)
    print(f"dy = {dy:+3d} : count = {len(dxs):2d}, dx in [{min(dxs):+3d}, {max(dxs):+3d}]")


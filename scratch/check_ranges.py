def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

for parity in [0, 1]:
    center_cx, center_cy = 10, 10 + parity
    c_pos = cell_to_world(center_cx, center_cy)
    
    # Let's search a wide range:
    found_dx = set()
    found_dy = set()
    all_cells = []
    for dy in range(-50, 51):
        for dx in range(-50, 50):
            cx = center_cx + dx
            cy = center_cy + dy
            wp = cell_to_world(cx, cy)
            rel_x = wp[0] - c_pos[0]
            rel_y = wp[1] - c_pos[1]
            u = (rel_x / 64.0) + (rel_y / 32.0)
            v = (rel_y / 32.0) - (rel_x / 64.0)
            if abs(u) <= limit and abs(v) <= limit:
                found_dx.add(dx)
                found_dy.add(dy)
                all_cells.append((dx, dy, u, v))
                
    print(f"Parity {parity} (cy={center_cy}):")
    print(f"  Total cells in diamond: {len(all_cells)}")
    print(f"  dx range: [{min(found_dx)}, {max(found_dx)}]")
    print(f"  dy range: [{min(found_dy)}, {max(found_dy)}]")


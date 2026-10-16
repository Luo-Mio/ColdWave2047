import json

# Let's simulate the exact logic:
# center_cell = (4, 28) (even row)
render_radius = 9
limit = render_radius + 0.5 # 9.5

# cell_to_world for staggered:
# if y is even: x*64 + 32, y*16 + 16
# if y is odd:  x*64 + 64, y*16 + 16
def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

for center_cy in [28, 27]:
    center_cx = 4
    c_pos = cell_to_world(center_cx, center_cy)
    
    max_dy = render_radius * 2
    max_dx = int(render_radius * 1.3 + 1)
    
    tiles = []
    for dy in range(-max_dy, max_dy + 1):
        for dx in range(-max_dx, max_dx + 1):
            cx = center_cx + dx
            cy = center_cy + dy
            wp = cell_to_world(cx, cy)
            rel_x = wp[0] - c_pos[0]
            rel_y = wp[1] - c_pos[1]
            u = (rel_x / 64.0) + (rel_y / 32.0)
            v = (rel_y / 32.0) - (rel_x / 64.0)
            if abs(u) <= limit and abs(v) <= limit:
                tiles.append((cx, cy, rel_x, rel_y, u, v))
                
    print(f"=== Center cell ({center_cx}, {center_cy}) (cy%2={center_cy%2}) Total tiles: {len(tiles)} ===")
    
    # Check screen bounds
    xs = [t[2] for t in tiles]
    ys = [t[3] for t in tiles]
    print(f"Screen rel X: min={min(xs)}, max={max(xs)}")
    print(f"Screen rel Y: min={min(ys)}, max={max(ys)}")
    
    # Check tiles along the 4 diagonal directions from center:
    # SE direction: +32, +16. (u increases, v=0)
    # NW direction: -32, -16. (u decreases, v=0)
    # SW direction: -32, +16. (v increases, u=0)
    # NE direction: +32, -16. (v decreases, u=0)
    se_tiles = [t for t in tiles if abs(t[5]) < 0.01 and t[4] >= 0]
    nw_tiles = [t for t in tiles if abs(t[5]) < 0.01 and t[4] <= 0]
    sw_tiles = [t for t in tiles if abs(t[4]) < 0.01 and t[5] >= 0]
    ne_tiles = [t for t in tiles if abs(t[4]) < 0.01 and t[5] <= 0]
    
    print(f"SE tiles along main diagonal (u>=0, v=0): count = {len(se_tiles)}, max u = {max([t[4] for t in se_tiles])}")
    print(f"NW tiles along main diagonal (u<=0, v=0): count = {len(nw_tiles)}, min u = {min([t[4] for t in nw_tiles])}")
    print(f"SW tiles along main diagonal (v>=0, u=0): count = {len(sw_tiles)}, max v = {max([t[5] for t in sw_tiles])}")
    print(f"NE tiles along main diagonal (v<=0, u=0): count = {len(ne_tiles)}, min v = {min([t[5] for t in ne_tiles])}")


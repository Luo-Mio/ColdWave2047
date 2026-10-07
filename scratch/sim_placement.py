# Simulation of placing 1 turf at (0, 0)
MASK_TO_ATLAS = [
	(0, 3), # 0:  0000
	(3, 3), # 1:  0001 (T)
	(0, 2), # 2:  0010 (R)
	(1, 2), # 3:  0011 (T+R)
	(0, 0), # 4:  0100 (L)
	(3, 2), # 5:  0101 (T+L)
	(2, 3), # 6:  0110 (R+L)
	(3, 1), # 7:  0111 (T+R+L)
	(1, 3), # 8:  1000 (B)
	(0, 1), # 9:  1001 (T+B)
	(1, 0), # 10: 1010 (R+B)
	(2, 2), # 11: 1011 (T+R+B)
	(3, 0), # 12: 1100 (L+B)
	(2, 0), # 13: 1101 (T+L+B)
	(1, 1), # 14: 1110 (R+L+B)
	(2, 1), # 15: 1111 (All 4)
]

# We placed turf at (0, 0)
turf_grid = {(0, 0): True}

def has_turf(x, y):
    return (x, y) in turf_grid

affected = [
    (0, 0),
    (-1, 0),
    (0, -1),
    (-1, -1),
]

for (u, v) in affected:
    mask = 0
    if has_turf(u, v):         mask |= 1
    if has_turf(u + 1, v):     mask |= 2
    if has_turf(u, v + 1):     mask |= 4
    if has_turf(u + 1, v + 1): mask |= 8
    
    tile = MASK_TO_ATLAS[mask]
    # dual cell (u, v) center in world:
    # layer position = (0, 16)
    # map_to_local(u, v): x = (u - v) * 32, y = (u + v) * 16
    pos_x = (u - v) * 32
    pos_y = (u + v) * 16 + 16
    print(f"Dual Cell ({u:2}, {v:2}): mask={mask:2} ({mask:04b}), Atlas Tile={tile}, World Pos=({pos_x:3}, {pos_y:3})")


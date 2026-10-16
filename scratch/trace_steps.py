# Let's inspect the 4 directions on the tilemap:
# How do (cx, cy) change when moving in the 4 grid directions?
# Let's trace from (cx, cy):

# In Isometric Staggered (tile_layout = 0, tile_shape = 1):
# Starting at an EVEN cy:
# Cell (cx, cy) is at (cx*64 + 32, cy*16 + 16).
# If we want to move Southeast (+32, +16):
# The neighbor at (+32, +16) is:
# new_y = cy + 1 (odd row).
# on odd row, x_pixel = new_cx*64 + 64.
# We want x_pixel = (cx*64 + 32) + 32 = cx*64 + 64.
# So new_cx = cx!
# So from EVEN row:
# Step 1 SE: (cx, cy) -> (cx, cy + 1).   delta = (+0, +1)
# Now from ODD row (cy + 1):
# We want to move another SE (+32, +16):
# new_y = cy + 2 (even row).
# on even row, x_pixel = new_cx*64 + 32.
# Previous x_pixel was cx*64 + 64.
# new x_pixel = cx*64 + 64 + 32 = cx*64 + 96 = (cx + 1)*64 + 32!
# So new_cx = cx + 1!
# Step 2 SE: (cx, cy + 1) -> (cx + 1, cy + 2). delta = (+1, +1)

print("Starting from (0, 0) [even]:")
c = [0, 0]
for i in range(10):
    print(f"Step {i} SE: {c}")
    if c[1] % 2 == 0:
        c = [c[0], c[1] + 1]
    else:
        c = [c[0] + 1, c[1] + 1]

print("\nStarting from (0, 0) [even] NW (-32, -16):")
c = [0, 0]
for i in range(10):
    print(f"Step {i} NW: {c}")
    if c[1] % 2 == 0:
        c = [c[0] - 1, c[1] - 1]
    else:
        c = [c[0], c[1] - 1]


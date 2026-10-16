# Let's map every tile to its (u, v) integer coordinate:
# Since u and v are integers from -9 to 9:
# u is SE (+u) / NW (-u)
# v is SW (+v) / NE (-v)

# In screen space:
# Top is North: rel_x = 0, rel_y = -288. (u = -9, v = -9)
# Bottom is South: rel_x = 0, rel_y = +288. (u = +9, v = +9)
# Left is West: rel_x = -576, rel_y = 0. (u = -9, v = +9)
# Right is East: rel_x = +576, rel_y = 0. (u = +9, v = -9)

print("North vertex: u = -9, v = -9")
print("South vertex: u = +9, v = +9")
print("West vertex:  u = -9, v = +9")
print("East vertex:  u = +9, v = -9")

# What are the 4 quadrants / directions?
# Positive rel_y is South. Positive rel_x is East.
# Southeast: rel_x > 0 and rel_y > 0.
# In (u, v):
# rel_x = 32 * (u - v)
# rel_y = 16 * (u + v)
#
# Look at rel_x and rel_y:
# When rel_x > 0: u > v.
# When rel_y > 0: u + v > 0.
# So Southeast is the quadrant between East and South!
# That is: u > 0 and v < u (so positive rel_x and rel_y).
# Specifically:
# East vertex is (+576, 0): u = +9, v = -9.
# South vertex is (0, +288): u = +9, v = +9.
# The boundary between East and South is: u = +9, with v from -9 to +9!
# THAT IS THE SOUTHEAST BOUNDARY!
# THE SOUTHEAST BOUNDARY HAS u = +9!
# THE NORTHWEST BOUNDARY HAS u = -9!
# THE NORTHEAST BOUNDARY HAS v = -9!
# THE SOUTHWEST BOUNDARY HAS v = +9!

print("SE boundary: u = +9")
print("NW boundary: u = -9")
print("NE boundary: u = anything, v = -9")
print("SW boundary: u = anything, v = +9")


from inspect_png import parse_png

w, h, pixels = parse_png(r"C:\Users\chris\.gemini\antigravity\brain\2038ed65-adf9-4ed0-aa13-b78032cdd916\.user_uploaded\media_1791379926619_72590117.png")

green_coords = []
for y in range(h):
    for x in range(w):
        idx = (y * w + x) * 4
        r, g, b, a = pixels[idx], pixels[idx+1], pixels[idx+2], pixels[idx+3]
        if a > 128 and g > r + 20 and g > b + 20:
            green_coords.append((x, y))

# Let's filter patch 1 (y < 150)
p1 = [c for c in green_coords if c[1] < 150]
print("Patch 1 total green pixels:", len(p1))
# Find min/max for patch 1
print("Patch 1 bbox:", min(c[0] for c in p1), max(c[0] for c in p1), min(c[1] for c in p1), max(c[1] for c in p1))

# Let's find connected components or x-range
p1_left = [c for c in p1 if c[0] < 125]
p1_right = [c for c in p1 if c[0] >= 125]
print("P1 left bbox:", min(c[0] for c in p1_left), max(c[0] for c in p1_left), min(c[1] for c in p1_left), max(c[1] for c in p1_left))
print("P1 right bbox:", min(c[0] for c in p1_right), max(c[0] for c in p1_right), min(c[1] for c in p1_right), max(c[1] for c in p1_right))


from inspect_png import parse_png
import struct

w, h, pixels = parse_png(r"C:\Users\chris\.gemini\antigravity\brain\2038ed65-adf9-4ed0-aa13-b78032cdd916\.user_uploaded\media_1791379926619_72590117.png")
print("User image size:", w, h)

# Let's find all green pixels (where G > R and G > B and G > 50)
green_coords = []
for y in range(h):
    for x in range(w):
        idx = (y * w + x) * 4
        r, g, b, a = pixels[idx], pixels[idx+1], pixels[idx+2], pixels[idx+3]
        if a > 128 and g > r + 20 and g > b + 20:
            green_coords.append((x, y))

if green_coords:
    min_x = min(c[0] for c in green_coords)
    max_x = max(c[0] for c in green_coords)
    min_y = min(c[1] for c in green_coords)
    max_y = max(c[1] for c in green_coords)
    print(f"Green bbox: x=[{min_x}, {max_x}], y=[{min_y}, {max_y}] (w={max_x - min_x + 1}, h={max_y - min_y + 1})")


from PIL import Image, ImageDraw

def cell_to_world(cx, cy):
    x = cx * 64.0 + (64.0 if (cy % 2 == 1) else 32.0)
    y = cy * 16.0 + 16.0
    return x, y

render_radius = 9
limit = render_radius + 0.5

center_cx, center_cy = 4, 28
c_pos = cell_to_world(center_cx, center_cy)

rendered_cells = []
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
            rendered_cells.append((cx, cy, wp[0], wp[1], rel_x, rel_y, u, v))

# Canvas size
width, height = 1400, 800
img = Image.new("RGBA", (width, height), (30, 30, 30, 255))
draw = ImageDraw.Draw(img)

# Center of image is c_pos
img_cx, img_cy = width // 2, height // 2

for c in rendered_cells:
    cx, cy, wx, wy, rx, ry, u, v = c
    sx = img_cx + rx
    sy = img_cy + ry
    
    # Diamond vertices:
    # (sx, sy - 16), (sx + 32, sy), (sx, sy + 16), (sx - 32, sy)
    pts = [(sx, sy - 16), (sx + 32, sy), (sx, sy + 16), (sx - 32, sy)]
    
    fill_col = (110, 75, 55, 255)
    if cx == center_cx and cy == center_cy:
        fill_col = (200, 50, 50, 255) # Red for center
    draw.polygon(pts, fill=fill_col, outline=(50, 35, 25, 255))

# Draw axes
draw.line([(img_cx - 650, img_cy), (img_cx + 650, img_cy)], fill=(100, 255, 100, 150), width=1) # Horizontal
draw.line([(img_cx, img_cy - 350), (img_cx, img_cy + 350)], fill=(100, 100, 255, 150), width=1) # Vertical

img.save("scratch/diamond_vis.png")
print("Saved scratch/diamond_vis.png! Total tiles:", len(rendered_cells))


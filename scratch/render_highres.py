from PIL import Image, ImageDraw, ImageFont

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
            rendered_cells.append((dx, dy, rel_x, rel_y, round(u), round(v)))

width, height = 2400, 1400
scale = 1.8
img = Image.new("RGBA", (width, height), (25, 25, 28, 255))
draw = ImageDraw.Draw(img)

img_cx, img_cy = width // 2, height // 2

try:
    font = ImageFont.truetype("arial.ttf", 10)
except:
    font = ImageFont.load_default()

for c in rendered_cells:
    dx, dy, rx, ry, u, v = c
    sx = img_cx + rx * scale
    sy = img_cy + ry * scale
    
    w2 = 32.0 * scale
    h2 = 16.0 * scale
    pts = [(sx, sy - h2), (sx + w2, sy), (sx, sy + h2), (sx - w2, sy)]
    
    # Color by (u, v) or center
    if dx == 0 and dy == 0:
        fill_col = (220, 60, 60, 255)
    elif u == 9:
        fill_col = (80, 140, 200, 255) # SE boundary (u=9)
    elif u == -9:
        fill_col = (200, 140, 80, 255) # NW boundary (u=-9)
    elif v == 9:
        fill_col = (140, 200, 80, 255) # SW boundary (v=9)
    elif v == -9:
        fill_col = (200, 80, 200, 255) # NE boundary (v=-9)
    else:
        # checkerboard slightly
        val = 110 + (dx % 2) * 10 + (dy % 2) * 10
        fill_col = (val, int(val * 0.7), int(val * 0.5), 255)
        
    draw.polygon(pts, fill=fill_col, outline=(30, 20, 15, 255))
    
    # Text: u,v
    txt = f"{u},{v}"
    draw.text((sx - 10, sy - 5), txt, fill=(240, 240, 240, 200), font=font)

# Draw cardinal lines
draw.line([(img_cx - 1100, img_cy), (img_cx + 1100, img_cy)], fill=(0, 255, 0, 120), width=2)
draw.line([(img_cx, img_cy - 600), (img_cx, img_cy + 600)], fill=(0, 150, 255, 120), width=2)

img.save("scratch/diamond_detailed.png")
print("Saved scratch/diamond_detailed.png!")


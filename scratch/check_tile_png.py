from PIL import Image

img = Image.open("resources/tiles/dirt_tile.png")
print("dirt_tile.png size:", img.size)

# Find bounding box of non-transparent pixels in dirt_tile.png:
bbox = img.getbbox()
print("Non-transparent bbox:", bbox)


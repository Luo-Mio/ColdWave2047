# Let's inspect scene/main_scene.tscn to see what layer1 tile_map_data has!
import base64
import struct

with open("scene/main_scene.tscn", "r", encoding="utf-8") as f:
    content = f.read()

# Find layer1
pos = content.find('[node name="layer1"')
if pos != -1:
    end_pos = content.find('[node name=', pos + 1)
    l1_text = content[pos:end_pos]
    print("Found layer1 in main_scene.tscn:")
    for line in l1_text.splitlines()[:10]:
        print("  ", line[:80])
    
    # Check if tile_map_data is there:
    import re
    m = re.search(r'tile_map_data\s*=\s*PackedByteArray\("([^"]+)"\)', l1_text)
    if m:
        b64_data = m.group(1)
        raw_bytes = base64.b64decode(b64_data)
        # In Godot 4, tile_map_data format:
        # Each tile is 12 bytes:
        # int16 x, int16 y, int16 layer, int16 source_id, int16 atlas_x, int16 atlas_y, ...
        # Or let's check size:
        print("Raw bytes length:", len(raw_bytes))
        num_tiles = len(raw_bytes) // 12
        print("Number of tiles in layer1 packed data:", num_tiles)


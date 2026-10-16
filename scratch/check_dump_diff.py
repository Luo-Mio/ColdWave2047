import json
import subprocess

# Let's inspect git diff of data/editor_map_dump.json
cmd = 'git diff data/editor_map_dump.json'
proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
diff_lines = proc.stdout.splitlines()

added_tiles = []
for line in diff_lines:
    if line.startswith('+') and not line.startswith('+++'):
        pass

# Instead of parsing diff text, let's load HEAD vs Working Tree:
head_json_str = subprocess.run('git show HEAD:data/editor_map_dump.json', shell=True, capture_output=True, text=True).stdout
with open('data/editor_map_dump.json', 'r') as f:
    work_dump = json.load(f)

head_dump = json.loads(head_json_str)

head_tiles = set((t['x'], t['y'], t['z']) for t in head_dump.get('tiles', []))
work_tiles = set((t['x'], t['y'], t['z']) for t in work_dump.get('tiles', []))

new_tiles = work_tiles - head_tiles
removed_tiles = head_tiles - work_tiles

print(f"Head tiles: {len(head_tiles)}, Work tiles: {len(work_tiles)}")
print(f"New tiles in work: {len(new_tiles)}, Removed tiles: {len(removed_tiles)}")

# What are the new tiles?
if new_tiles:
    min_x = min(t[0] for t in new_tiles)
    max_x = max(t[0] for t in new_tiles)
    min_y = min(t[1] for t in new_tiles)
    max_y = max(t[1] for t in new_tiles)
    print(f"New tiles bounds: X=[{min_x}, {max_x}], Y=[{min_y}, {max_y}]")
    print(f"Sample new tiles: {list(new_tiles)[:10]}")


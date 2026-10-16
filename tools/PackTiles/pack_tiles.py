import os
import re
import sys
import math
import argparse
from PIL import Image

def natural_sort_key(s):
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

def pack_tiles(target_dir: str = None, cols: int = None, output_name: str = "atlas.png") -> str:
    # 默认使用本脚本所在的当前目录
    if not target_dir:
        target_dir = os.path.dirname(os.path.abspath(__file__))
    
    if not os.path.isdir(target_dir):
        print(f"[错误] 目录不存在: {target_dir}")
        return ""
    
    # 查找目录下所有 .png 散图（自动排除已生成的 atlas 文件）
    png_files = [
        f for f in os.listdir(target_dir)
        if f.lower().endswith(".png") and not f.lower().endswith("_atlas.png") and f.lower() != output_name.lower()
    ]
    
    if not png_files:
        print(f"[提示] 在当前目录中未找到可合并的 .png 图片！")
        print(f"      请将要合并的瓷砖图片拖入本文件夹: {target_dir}")
        return ""
    
    # 自然数字排序 (如 001.png, 002.png, ... 009.png, 010.png)
    png_files.sort(key=natural_sort_key)
    
    print(f"==================================================")
    print(f"工作目录: {target_dir}")
    print(f"找到 {len(png_files)} 张待合并散图:")
    images = []
    base_w, base_h = None, None
    for f in png_files:
        p = os.path.join(target_dir, f)
        try:
            img = Image.open(p).convert("RGBA")
        except Exception as e:
            print(f"  [跳过] 无法读取图片 {f}: {e}")
            continue
            
        if base_w is None:
            base_w, base_h = img.size
        elif img.size != (base_w, base_h):
            print(f"  [警告] 图片 {f} 尺寸 ({img.size[0]}x{img.size[1]}) 与首张 ({base_w}x{base_h}) 不一致！")
        images.append((f, img))
        print(f"  - {f} ({img.size[0]}x{img.size[1]})")
    
    total = len(images)
    if total == 0:
        return ""
    
    # 如果未指定列数，自动计算智能列数 (如 9张默认3列，4张默认2列，其余默认 3列 或 总数)
    if cols is None or cols <= 0:
        sqrt_n = int(math.isqrt(total))
        if sqrt_n * sqrt_n == total:
            num_cols = sqrt_n
        elif total <= 4:
            num_cols = total
        else:
            num_cols = 3
    else:
        num_cols = min(cols, total)
        
    num_rows = (total + num_cols - 1) // num_cols
    
    sheet_w = num_cols * base_w
    sheet_h = num_rows * base_h
    
    # 创建透明底板
    atlas = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    
    for idx, (fname, img) in enumerate(images):
        c = idx % num_cols
        r = idx // num_cols
        atlas.paste(img, (c * base_w, r * base_h))
    
    output_path = os.path.join(target_dir, output_name)
    atlas.save(output_path, "PNG")
    print(f"==================================================")
    print(f"[成功] 图集已生成！")
    print(f"  输出文件: {output_path}")
    print(f"  图集分辨率: {sheet_w}x{sheet_h} ({num_cols} 列 x {num_rows} 行)")
    print(f"  单块尺寸: {base_w}x{base_h}")
    print(f"==================================================")
    return output_path

if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="将单张瓷砖图合并为 TileSet 图集 (Atlas)")
    parser.add_argument("--dir", "-d", default=current_dir, help="目标瓷砖目录 (默认: 脚本所在目录)")
    parser.add_argument("--cols", "-c", type=int, default=None, help="合并后的列数 (默认: 智能计算，如9张默认3列)")
    parser.add_argument("--output", "-o", default="atlas.png", help="输出文件名 (默认: atlas.png)")
    
    args = parser.parse_args()
    pack_tiles(args.dir, args.cols, args.output)


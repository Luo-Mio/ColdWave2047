shader_type canvas_item;

global uniform vec2 player_world_pos;

uniform float rx : hint_range(4.0, 400.0) = 85.0;
uniform float ry : hint_range(4.0, 400.0) = 55.0;
uniform float feather : hint_range(0.01, 1.0) = 0.8;

// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

varying vec2 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    if (col.a <= 0.001) { discard; }

    vec2 diff = (v_world_pos - player_world_pos) / vec2(rx, ry);
    float dist_sq = dot(diff, diff);

    if (dist_sq < 1.0) {
        // 计算遮罩强度 (0.0=最外侧, 1.0=最中心)
        float mask = 1.0 - smoothstep(1.0 - feather, 1.0, dist_sq);

        // 像素点阵抖动：利用屏幕绝对像素对齐镂空
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float dither_threshold = bayer[x][y];

        // 越靠近中心，被剔除的像素越多；多层树木叠加时镂空点完全重合，绝不叠加变暗！
        if (mask * 0.85 > dither_threshold) {
            discard;
        }
    }

    COLOR = col;
}
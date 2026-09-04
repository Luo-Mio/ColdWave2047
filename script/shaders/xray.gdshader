shader_type canvas_item;

global uniform vec2 player_world_pos;
global uniform vec2 player_facing_dir;
global uniform float vision_fov;
global uniform sampler2D vision_mask_tex;
global uniform vec2 vision_cam_pos;
global uniform vec2 vision_cam_zoom;
global uniform vec2 vision_screen_size;

// 透视中心相对于角色脚底坐标的世界偏移量 (例如 (0, -24) 可将透视中心上移至角色面部/胸部)
uniform vec2 target_offset = vec2(0.0, 0.0);

uniform float rx : hint_range(4.0, 400.0) = 85.0;
uniform float ry : hint_range(4.0, 400.0) = 55.0;
uniform float feather : hint_range(0.01, 1.0) = 0.8;
uniform float max_transparency : hint_range(0.0, 1.0) = 0.85; // 0.0=完全实心, 1.0=中心完全镂空透明

// 视线/高物常态点阵透视参数
uniform bool enable_vision_xray = false;
uniform float vision_transparency : hint_range(0.0, 1.0) = 0.70; // 树叶点阵镂空穿透度 (0.7=70%镂空，露出树后地面与生物)

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

    // 0. 视野开角限制：透明遮罩仅对正面视野内的物体生效，背后的树冠/物体保持完全实心渲染
    float in_fov = 1.0;
    if (vision_fov > 0.0 && vision_fov < 359.0 && length(player_facing_dir) > 0.001) {
        vec2 to_pixel = v_world_pos - player_world_pos;
        float dist = length(to_pixel);
        if (dist > 1.0) {
            vec2 dir_to_pixel = to_pixel / dist;
            float cos_angle = dot(dir_to_pixel, normalize(player_facing_dir));
            float half_fov_rad = radians(vision_fov * 0.5);
            float cos_limit = cos(half_fov_rad);
            // 边缘平滑羽化过渡（约 5°），避免硬切割线
            in_fov = smoothstep(cos_limit - 0.08, cos_limit + 0.04, cos_angle);
        }
    }

    // 1. 近身椭圆透视 (针对角色走到树木近处/面部)
    vec2 target_pos = player_world_pos + target_offset;
    vec2 diff = (v_world_pos - target_pos) / vec2(rx, ry);
    float dist_sq = dot(diff, diff);
    float proximity_mask = 0.0;
    if (dist_sq < 1.0) {
        proximity_mask = (1.0 - smoothstep(1.0 - feather, 1.0, dist_sq)) * max_transparency;
    }

    // 2. 树冠高物常态透视 (当开启透视时，使树冠在正面视野内呈现半透明点阵，清晰露出树下地面与生物)
    float vision_mask = 0.0;
    if (enable_vision_xray) {
        vision_mask = vision_transparency;
    }

    // 3. 综合多路遮罩镂空，乘以视野系数 (视野不可见的部分不再渲染透明遮罩，背后的树冠完全实心渲染！)
    float final_mask = max(proximity_mask, vision_mask) * in_fov;

    if (final_mask > 0.0) {
        // 像素点阵抖动：利用屏幕绝对像素对齐镂空
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float dither_threshold = bayer[x][y];

        // 越靠近中心或视线照射越充分，被剔除的像素越多
        if (final_mask > dither_threshold) {
            discard;
        }
    }

    COLOR = col;
}
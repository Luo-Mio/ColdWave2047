shader_type canvas_item;

// 接收角色的纯世界坐标（不受全屏、分辨率、摄像机任何影响）
global uniform vec2 player_world_pos;

// 世界像素半径（建议 rx = 60~90, ry = 40~60）
uniform float rx : hint_range(8.0, 400.0) = 75.0;
uniform float ry : hint_range(8.0, 400.0) = 50.0;
uniform float target_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float feather : hint_range(0.01, 1.0) = 0.8;

// 传递给片段着色器的世界坐标
varying vec2 v_world_pos;

void vertex() {
    // 将顶点局部坐标转换为绝对的世界坐标
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    if (col.a <= 0.001) { discard; }

    // 直接在世界空间比对物体像素与角色脚底的距离
    vec2 diff = (v_world_pos - player_world_pos) / vec2(rx, ry);
    float dist_sq = dot(diff, diff);

    if (dist_sq < 1.0) {
        float mask = 1.0 - smoothstep(1.0 - feather, 1.0, dist_sq);
        col.a *= mix(1.0, target_alpha, mask);
    }

    COLOR = col;
}
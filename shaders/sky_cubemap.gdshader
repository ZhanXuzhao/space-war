shader_type sky;

uniform sampler2D face_right;
uniform sampler2D face_left;
uniform sampler2D face_top;
uniform sampler2D face_bottom;
uniform sampler2D face_front;
uniform sampler2D face_back;

vec4 sample_cubemap(vec3 dir) {
	vec3 abs_dir = abs(dir);
	float max_axis = max(max(abs_dir.x, abs_dir.y), abs_dir.z);
	vec2 uv;
	vec4 color;

	if (max_axis == abs_dir.x) {
		// +X / -X 面（右 / 左）
		if (dir.x > 0.0) {
			// +X: Right face
			uv = vec2(dir.z, -dir.y) / abs_dir.x * 0.5 + 0.5;
			color = texture(face_right, uv);
		} else {
			// -X: Left face
			uv = vec2(-dir.z, -dir.y) / abs_dir.x * 0.5 + 0.5;
			color = texture(face_left, uv);
		}
	} else if (max_axis == abs_dir.y) {
		// +Y / -Y 面（上 / 下）
		if (dir.y > 0.0) {
			// +Y: Top face
			uv = vec2(dir.x, dir.z) / abs_dir.y * 0.5 + 0.5;
			color = texture(face_top, uv);
		} else {
			// -Y: Bottom face
			uv = vec2(dir.x, -dir.z) / abs_dir.y * 0.5 + 0.5;
			color = texture(face_bottom, uv);
		}
	} else {
		// +Z / -Z 面（前 / 后）
		if (dir.z > 0.0) {
			// +Z: Front face
			uv = vec2(-dir.x, -dir.y) / abs_dir.z * 0.5 + 0.5;
			color = texture(face_front, uv);
		} else {
			// -Z: Back face
			uv = vec2(dir.x, -dir.y) / abs_dir.z * 0.5 + 0.5;
			color = texture(face_back, uv);
		}
	}

	return color;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	COLOR = sample_cubemap(dir).rgb;
}

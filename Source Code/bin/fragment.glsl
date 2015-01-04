uniform int initialized;
uniform sampler2D texUnit;

/**
 * Initialize the image.
 * 
 * Use red component as U and blue component as V of Gray-Scott model.
 */
void init()
{
	vec2 texCoord = gl_TexCoord[0].xy;

	if (texCoord.x > 0.48 && texCoord.x < 0.52 && texCoord.y > 0.48 && texCoord.y < 0.52) {
		gl_FragColor = vec4(0.5, 0.0, 0.25, 1.0);
	} else {
		gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
	}
}

/**
 * Update the color of each pixel.
 *
 * Use Gray-Scott reaction-diffusion model to update U and V,
 * and U and V are stored in red and blue components of the pixel color, respectively.
 */
void update()
{
	const float offset = 1.0 / 512.0;
	
	vec2 texCoord = gl_TexCoord[0].xy;

	// parameters for Gray-Scott model
	float F = 0.037;
	float K = 0.06;
	float Du = 0.209;
	float Dv = 0.102;

	// get the colors of the pixels
	vec2 c = texture2D(texUnit, texCoord).rb;
	vec2 l = texture2D(texUnit, texCoord + vec2(-offset, 0.0)).rb;
	vec2 t = texture2D(texUnit, texCoord + vec2(0.0, offset)).rb;
	vec2 r = texture2D(texUnit, texCoord + vec2(offset, 0.0)).rb;
	vec2 b = texture2D(texUnit, texCoord + vec2(0.0, -offset)).rb;

	float U = c.x;
	float V = c.y;
	vec2 lap = l + t + r + b  - c * 4.0;

	float dU = Du * lap.x - U * V * V + F * (1.0 - U);
	float dV = Dv * lap.y + U * V * V - (F + K) * V;

	// use the heat equation to updte the color of this pixel
	gl_FragColor = vec4(U + dU, 0.0, V + dV, 1.0);
}

void main()
{
	if (initialized == 0) {
		init();
	} else {
		update();
	}
}
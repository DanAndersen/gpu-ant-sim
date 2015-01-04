#version 150 compatibility

// will be used for determining gradient for shading
in vec4 position;
in vec3 normal;
in vec3 v;
in vec4 diffuse;

void main()
{
	vec3 lightVector = normalize(gl_LightSource[0].position.xyz - v);

	vec4 Idiff = diffuse * max(dot(normal, lightVector), 0.0);
	Idiff = clamp(Idiff, 0.0, 1.0);
	gl_FragColor = Idiff;
}
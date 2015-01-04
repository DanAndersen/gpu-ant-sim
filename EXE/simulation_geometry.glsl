#version 150 compatibility

layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

in int vertexInstance[3];

out float volumeLayer;

void main()
{
	gl_Layer = vertexInstance[0];

	volumeLayer = float(gl_Layer) + 0.5;

	gl_Position = gl_in[0].gl_Position;
    EmitVertex();
    gl_Position = gl_in[1].gl_Position;
    EmitVertex();
    gl_Position = gl_in[2].gl_Position;
    EmitVertex();
    EndPrimitive();
}
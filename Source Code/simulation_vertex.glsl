#version 140

in vec4 Position;
out int vertexInstance;

void main()
{
	gl_Position = Position;
	vertexInstance = gl_InstanceID;
}
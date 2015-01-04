#version 150 compatibility

void main()
{
	gl_TexCoord[0]=gl_MultiTexCoord0;

	gl_Position = gl_Vertex;

	gl_FrontColor = gl_Color;
}
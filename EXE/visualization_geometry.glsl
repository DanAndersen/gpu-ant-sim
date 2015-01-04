// using compatibility mode here because gl_ModelViewProjectionMatrix is deprecated
#version 150 compatibility

#extension GL_EXT_geometry_shader4 : enable 
#extension GL_EXT_gpu_shader4 : enable 

// Based on: "OpenGL Geometry Shader Marching Cubes": http://www.icare3d.org/codes-and-projects/codes/opengl_geometry_shader_marching_cubes.html
// and "Polygonising a scalar field": http://paulbourke.net/geometry/polygonise/

layout(points) in;
layout(triangle_strip, max_vertices = 16) out;

uniform vec3 voxelSize;
uniform sampler3D worldTexture;
uniform isampler2D triangleTableTexture;

uniform vec3 inverseWorldTextureSize;

uniform vec3 cubeVertexDecals[8];

uniform float trailOpacity;

// will be used in fragment shader
out vec4 position;
out vec3 normal;
out vec3 v;
out vec4 diffuse;

const int NUM_CUBE_VERTICES = 8;

const float TRAIL_THRESHOLD = 0.0;	// if it's above this amount, it should display
const float NEST_THRESHOLD = 0.0;
const float FOOD_THRESHOLD = 0.0;
const float ANT_THRESHOLD = 0.0;

vec3 cubeVertexPosition(int vertexIndex) {
	return gl_in[0].gl_Position.xyz + cubeVertexDecals[vertexIndex];
}

vec4 lookupWorldCellColorAtCubeVertexPosition(vec3 cubeVertexPosition) {
	// the vertex index tells which offset to use (each offset is in the range (0,0,0) to (voxelSize.x, voxelSize.y, vozelSize.z))
	// meaning it either adds or doesn't add that voxel size value to the original position
	vec3 cubeVertexPositionInWorldTexture = (cubeVertexPosition + 1.0)/2.0 + (0.5 * inverseWorldTextureSize);
	vec4 worldCellColorAtCubeVertexPosition = texture3D(worldTexture, cubeVertexPositionInWorldTexture);
	return worldCellColorAtCubeVertexPosition;
}

// return value from 0.0 to 1.0
float trailValueInWorldCell(vec4 worldCellColor) {
	return worldCellColor.b;
}

float nestValueInWorldCell(vec4 worldCellColor) {
	return worldCellColor.r;
}

float foodValueInWorldCell(vec4 worldCellColor) {
	return worldCellColor.g;
}

float antValueInWorldCell(vec4 worldCellColor) {
	return worldCellColor.a;
}

bool worldCellContainsObject(vec4 worldCellColor) {
	if (worldCellColor.r > 0.0 || worldCellColor.g > 0.0 || worldCellColor.b > 0.0) {
		return true;	// nest, food, or trail
	}
	if (worldCellColor.a > 0.0) {
		return true;	// ant is present here
	}
	return false;
}

void emitTriangle(const vec4 v1, const vec4 v2, const vec4 v3, vec4 color) {
	diffuse = color;

	// calculating normals
	vec3 A = v3.xyz - v1.xyz;
	vec3 B = v2.xyz - v1.xyz;
	mat4 normalMatrix = transpose(inverse(gl_ModelViewMatrix));
	normal = mat3(normalMatrix) * normalize(cross(A,B));

	position = v1;
	v = vec3(gl_ModelViewMatrix * position);
	gl_Position = gl_ModelViewProjectionMatrix * position;
	EmitVertex();
			
	position = v2;
	v = vec3(gl_ModelViewMatrix * position);
	gl_Position = gl_ModelViewProjectionMatrix * position;
	EmitVertex();

	position = v3;
	v = vec3(gl_ModelViewMatrix * position);
	gl_Position = gl_ModelViewProjectionMatrix * position;
	EmitVertex();

	EndPrimitive();
}

vec3 vertexInterp(float threshold, vec3 point0, float value0, vec3 point1, float value1) {
	return mix(point0, point1, (threshold - value0)/(value1 - value0));
}

// do a lookup on the triangle table
int triangleTableValue(int edgeNumber, int triangleVertexNumber) {
	return texelFetch(triangleTableTexture, ivec2(triangleVertexNumber, edgeNumber), 0).a;
}

void doMarchingCubesTrail(float thresholdValue, vec3 cubeVertexPositions[NUM_CUBE_VERTICES], float surfaceValues[NUM_CUBE_VERTICES], int edgeTableIndex, vec4 displayColor) {
	if (edgeTableIndex != 0 && edgeTableIndex != 255) {	// only continue if we're not completely in/out of the surface
		
		vec3 vertexList[12];

		vertexList[0] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[1], surfaceValues[1]);
		vertexList[1] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[2], surfaceValues[2]);
		vertexList[2] =		vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[3], surfaceValues[3]);
		vertexList[3] =		vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[0], surfaceValues[0]);
		vertexList[4] =		vertexInterp(thresholdValue, cubeVertexPositions[4], surfaceValues[4], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[5] =		vertexInterp(thresholdValue, cubeVertexPositions[5], surfaceValues[5], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[6] =		vertexInterp(thresholdValue, cubeVertexPositions[6], surfaceValues[6], cubeVertexPositions[7], surfaceValues[7]);
		vertexList[7] =		vertexInterp(thresholdValue, cubeVertexPositions[7], surfaceValues[7], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[8] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[9] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[10] =	vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[11] =	vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[7], surfaceValues[7]);
	
		// now actually do lookups on the triangles and create some geometry
		int triangleTableIndex = 0;
		while(true) {
			int triangleTableValue_First = triangleTableValue(edgeTableIndex, triangleTableIndex+0);

			if (triangleTableValue_First != -1) {	// once we hit -1's, we're done, don't make more triangles

				emitTriangle(	vec4(vertexList[triangleTableValue_First], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+1)], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+2)], 1),
								displayColor);

			} else {
				break;
			}

			triangleTableIndex += 3;	// advance to next triangle in table
		}
	}
}


void doMarchingCubesFood(float thresholdValue, vec3 cubeVertexPositions[NUM_CUBE_VERTICES], float surfaceValues[NUM_CUBE_VERTICES], int edgeTableIndex, vec4 displayColor) {
	if (edgeTableIndex != 0 && edgeTableIndex != 255) {	// only continue if we're not completely in/out of the surface
		
		vec3 vertexList[12];
	
		// this is to darken the food as it's eaten
		float highestFoodValue = max(surfaceValues[0], surfaceValues[1]);
		highestFoodValue = max(highestFoodValue, surfaceValues[2]);
		highestFoodValue = max(highestFoodValue, surfaceValues[3]);
		highestFoodValue = max(highestFoodValue, surfaceValues[4]);
		highestFoodValue = max(highestFoodValue, surfaceValues[5]);
		highestFoodValue = max(highestFoodValue, surfaceValues[6]);
		highestFoodValue = max(highestFoodValue, surfaceValues[7]);

		displayColor = mix(vec4(0.0, 0.0, 0.0, 1.0), displayColor, highestFoodValue);

		vertexList[0] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[1], surfaceValues[1]);
		vertexList[1] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[2], surfaceValues[2]);
		vertexList[2] =		vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[3], surfaceValues[3]);
		vertexList[3] =		vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[0], surfaceValues[0]);
		vertexList[4] =		vertexInterp(thresholdValue, cubeVertexPositions[4], surfaceValues[4], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[5] =		vertexInterp(thresholdValue, cubeVertexPositions[5], surfaceValues[5], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[6] =		vertexInterp(thresholdValue, cubeVertexPositions[6], surfaceValues[6], cubeVertexPositions[7], surfaceValues[7]);
		vertexList[7] =		vertexInterp(thresholdValue, cubeVertexPositions[7], surfaceValues[7], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[8] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[9] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[10] =	vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[11] =	vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[7], surfaceValues[7]);

		// now actually do lookups on the triangles and create some geometry
		int triangleTableIndex = 0;
		while(true) {
			int triangleTableValue_First = triangleTableValue(edgeTableIndex, triangleTableIndex+0);

			if (triangleTableValue_First != -1) {	// once we hit -1's, we're done, don't make more triangles

				emitTriangle(	vec4(vertexList[triangleTableValue_First], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+1)], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+2)], 1),
								displayColor);

			} else {
				break;
			}

			triangleTableIndex += 3;	// advance to next triangle in table
		}
	}
}


void doMarchingCubesNest(float thresholdValue, vec3 cubeVertexPositions[NUM_CUBE_VERTICES], float surfaceValues[NUM_CUBE_VERTICES], int edgeTableIndex, vec4 displayColor) {
	if (edgeTableIndex != 0 && edgeTableIndex != 255) {	// only continue if we're not completely in/out of the surface
		
		vec3 vertexList[12];
	
		vertexList[0] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[1], surfaceValues[1]);
		vertexList[1] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[2], surfaceValues[2]);
		vertexList[2] =		vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[3], surfaceValues[3]);
		vertexList[3] =		vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[0], surfaceValues[0]);
		vertexList[4] =		vertexInterp(thresholdValue, cubeVertexPositions[4], surfaceValues[4], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[5] =		vertexInterp(thresholdValue, cubeVertexPositions[5], surfaceValues[5], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[6] =		vertexInterp(thresholdValue, cubeVertexPositions[6], surfaceValues[6], cubeVertexPositions[7], surfaceValues[7]);
		vertexList[7] =		vertexInterp(thresholdValue, cubeVertexPositions[7], surfaceValues[7], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[8] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[9] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[10] =	vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[11] =	vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[7], surfaceValues[7]);

		// now actually do lookups on the triangles and create some geometry
		int triangleTableIndex = 0;
		while(true) {
			int triangleTableValue_First = triangleTableValue(edgeTableIndex, triangleTableIndex+0);

			if (triangleTableValue_First != -1) {	// once we hit -1's, we're done, don't make more triangles

				emitTriangle(	vec4(vertexList[triangleTableValue_First], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+1)], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+2)], 1),
								displayColor);

			} else {
				break;
			}

			triangleTableIndex += 3;	// advance to next triangle in table
		}
	}
}

void doMarchingCubesAnt(float thresholdValue, vec3 cubeVertexPositions[NUM_CUBE_VERTICES], float surfaceValues[NUM_CUBE_VERTICES], int edgeTableIndex, vec4 displayColor) {
	if (edgeTableIndex != 0 && edgeTableIndex != 255) {	// only continue if we're not completely in/out of the surface
		
		vec3 vertexList[12];
	
		vertexList[0] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[1], surfaceValues[1]);
		vertexList[1] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[2], surfaceValues[2]);
		vertexList[2] =		vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[3], surfaceValues[3]);
		vertexList[3] =		vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[0], surfaceValues[0]);
		vertexList[4] =		vertexInterp(thresholdValue, cubeVertexPositions[4], surfaceValues[4], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[5] =		vertexInterp(thresholdValue, cubeVertexPositions[5], surfaceValues[5], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[6] =		vertexInterp(thresholdValue, cubeVertexPositions[6], surfaceValues[6], cubeVertexPositions[7], surfaceValues[7]);
		vertexList[7] =		vertexInterp(thresholdValue, cubeVertexPositions[7], surfaceValues[7], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[8] =		vertexInterp(thresholdValue, cubeVertexPositions[0], surfaceValues[0], cubeVertexPositions[4], surfaceValues[4]);
		vertexList[9] =		vertexInterp(thresholdValue, cubeVertexPositions[1], surfaceValues[1], cubeVertexPositions[5], surfaceValues[5]);
		vertexList[10] =	vertexInterp(thresholdValue, cubeVertexPositions[2], surfaceValues[2], cubeVertexPositions[6], surfaceValues[6]);
		vertexList[11] =	vertexInterp(thresholdValue, cubeVertexPositions[3], surfaceValues[3], cubeVertexPositions[7], surfaceValues[7]);

		// now actually do lookups on the triangles and create some geometry
		int triangleTableIndex = 0;
		while(true) {
			int triangleTableValue_First = triangleTableValue(edgeTableIndex, triangleTableIndex+0);

			if (triangleTableValue_First != -1) {	// once we hit -1's, we're done, don't make more triangles

				emitTriangle(	vec4(vertexList[triangleTableValue_First], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+1)], 1), 
								vec4(vertexList[triangleTableValue(edgeTableIndex, triangleTableIndex+2)], 1),
								displayColor);

			} else {
				break;
			}

			triangleTableIndex += 3;	// advance to next triangle in table
		}
	}
}

void main()
{

	// set up the edgeTableIndexes
	int trailEdgeTableIndex = 0;
	int nestEdgeTableIndex = 0;
	int foodEdgeTableIndex = 0;
	int antEdgeTableIndex = 0;

	vec3 cubeVertexPositions[NUM_CUBE_VERTICES];

	float trailValues[NUM_CUBE_VERTICES];
	float nestValues[NUM_CUBE_VERTICES];
	float foodValues[NUM_CUBE_VERTICES];
	float antValues[NUM_CUBE_VERTICES];
	int cubeVertexIndex;
	for (cubeVertexIndex = 0; cubeVertexIndex < NUM_CUBE_VERTICES; cubeVertexIndex++) {
		cubeVertexPositions[cubeVertexIndex] = cubeVertexPosition(cubeVertexIndex);
		vec4 worldCellColor = lookupWorldCellColorAtCubeVertexPosition(cubeVertexPositions[cubeVertexIndex]);
		trailValues[cubeVertexIndex] = trailValueInWorldCell(worldCellColor);
		nestValues[cubeVertexIndex] = nestValueInWorldCell(worldCellColor);
		foodValues[cubeVertexIndex] = foodValueInWorldCell(worldCellColor);
		antValues[cubeVertexIndex] = antValueInWorldCell(worldCellColor);

		if (trailValues[cubeVertexIndex] > TRAIL_THRESHOLD) {
			trailEdgeTableIndex += (1 << cubeVertexIndex);
		}
		if (nestValues[cubeVertexIndex] > NEST_THRESHOLD) {
			nestEdgeTableIndex += (1 << cubeVertexIndex);
		}
		if (foodValues[cubeVertexIndex] > FOOD_THRESHOLD) {
			foodEdgeTableIndex += (1 << cubeVertexIndex);
		}
		if (antValues[cubeVertexIndex] > ANT_THRESHOLD) {
			antEdgeTableIndex += (1 << cubeVertexIndex);
		}
	}

	// not entirely sure why, but having these call the same function leads to bad results

	doMarchingCubesTrail(TRAIL_THRESHOLD, cubeVertexPositions, trailValues, trailEdgeTableIndex, vec4(0.0, 0.0, 1.0, trailOpacity));

	doMarchingCubesFood(FOOD_THRESHOLD, cubeVertexPositions, foodValues, foodEdgeTableIndex, vec4(0.0, 1.0, 0.0, 1.0));

	doMarchingCubesNest(NEST_THRESHOLD, cubeVertexPositions, nestValues, nestEdgeTableIndex, vec4(1.0, 0.0, 0.0, 1.0));

	doMarchingCubesAnt(ANT_THRESHOLD, cubeVertexPositions, antValues, antEdgeTableIndex, vec4(1.0, 1.0, 1.0, 1.0));
	
}

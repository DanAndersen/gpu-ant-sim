#version 330

#extension GL_EXT_geometry_shader4 : enable 
#extension GL_EXT_gpu_shader4 : enable 

uniform int initialized;

uniform float randomSeed;
uniform float initialFoodRatio;
uniform float trailDissipationPerFrame;
uniform float foodPickupRate;

uniform sampler3D worldTexture;
uniform sampler3D antTexture;

uniform vec3 inverseWorldTextureSize;
uniform vec3 inverseAntTextureSize;

in float volumeLayer;

// pseudorandom seed
// http://byteblacksmith.com/improvements-to-the-canonical-one-liner-glsl-rand-for-opengl-es-2-0/
float rand(vec2 co)
{
    float a = 12.9898;
    float b = 78.233;
    float c = 43758.5453;
    float dt= dot(co.xy ,vec2(a,b));
    float sn= mod(dt,3.14);
    return fract(sin(sn) * c);
}

vec3 getWorldVolumeCoord() {
	return vec3(gl_FragCoord.xy, volumeLayer)-0.5;
}

vec3 lookupWorldTextureCoord() {
	// this represents which world voxel we're dealing with here
	vec3 worldVolumeCoord = getWorldVolumeCoord();		// in values [0,1,2,...,15]

	// this represents where to look in the world texture to find this world voxel
	vec3 worldTextureCoord = inverseWorldTextureSize*(worldVolumeCoord+0.5);	 // in values [0.5/16,1.5/16,2.5/16,...,15.5/16]
	return worldTextureCoord;
}

float getSeed() {
	vec3 worldTextureCoord = lookupWorldTextureCoord();

	// based on combo of frag coord and current color
	float fragCoordSeedXY = rand(worldTextureCoord.xy);
	float fragCoordSeedYZ = rand(worldTextureCoord.yz);

	float fragCoordSeedXYZ = rand(vec2(fragCoordSeedXY, fragCoordSeedYZ));

	return rand(vec2(fragCoordSeedXYZ, randomSeed));
}

float getRandBetween(float low, float high, float seed) {
	return mix(low,high,rand(vec2(seed,seed+1)));
}

vec4 getBaseWorldColor(vec4 lastFrameColor) {
	// red = nest
	// green = food
	// blue = trail
	// we don't want to persist info about the ant (alpha) if it's moved away
	return vec4(lastFrameColor.r, lastFrameColor.g, lastFrameColor.b, 0.0);
}

bool locationsOverlapOnWorld(vec3 queryLocation, vec3 targetLocation)
{
	vec3 distance = abs(targetLocation - queryLocation);

	return	(distance.x < 0.5) &&
			(distance.y < 0.5) &&
			(distance.z < 0.5);
}

float getDistanceBetweenLocations(vec3 a, vec3 b) {
	vec3 d = abs(a - b);
	return sqrt(pow(d.x,2) + pow(d.y,2) + pow(d.z,2));
}

void init()
{
	float seed = getSeed();

	vec3 worldVolumeCoord = getWorldVolumeCoord();	// in form [0, 1, ..., 15]

	vec3 centerOfWorld = 1.0 / inverseWorldTextureSize / 2.0;	// if texture size is 16x16x16, this gets element 8,8,8

	if (getDistanceBetweenLocations(centerOfWorld, worldVolumeCoord) < 2.0) {
		gl_FragColor = vec4(1.0, 0.0, 0.0, 0.0);	// establish the nest at the center of the world
	} else if (getRandBetween(0.0, 1.0, ++seed) < initialFoodRatio) {
		gl_FragColor = vec4(0.0, 1.0, 0.0, 0.0);	// put food here
	} else {
		gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);	// default; nothing here
	}
}

vec4 lookupWorldCellColorInTexture() {
	// this represents which world voxel we're dealing with here
	vec3 worldVolumeCoord = getWorldVolumeCoord();	// in values [0,1,2,...,15]

	// this represents where to look in the world texture to find this world voxel
	vec3 worldTextureCoord = inverseWorldTextureSize*(worldVolumeCoord+0.5); // in values [0.5/16,1.5/16,2.5/16,...,15.5/16]

	// this represents the current world state at this voxel
	vec4 worldCellColor = texture(worldTexture, worldTextureCoord);

	return worldCellColor;
}

// alpha defines ant state (direction, has-food)
// 32-bit float
const uint BITMASK_HAS_FOOD = 1u << 0;
const uint BITMASK_X_POS = 1u << 1;
const uint BITMASK_X_NEG = 1u << 2;
const uint BITMASK_Y_POS = 1u << 3;
const uint BITMASK_Y_NEG = 1u << 4;
const uint BITMASK_Z_POS = 1u << 5;
const uint BITMASK_Z_NEG = 1u << 6;

highp uint getAntStateFromColor(vec4 antCellColor) {
	highp uint antState = uint(antCellColor.a);
	return antState;
}

bool getHasFoodFromState(highp uint antState) {
	return ((antState & BITMASK_HAS_FOOD) > 0u);
}

vec3 getAntPositionInWorldFromColor(vec4 antCellColor) {
	return (antCellColor.xyz / inverseWorldTextureSize) - 0.5;
}

void update()
{
	vec4 worldCellColor = getBaseWorldColor(lookupWorldCellColorInTexture());

	vec3 worldVolumeCoord = getWorldVolumeCoord();

	vec3 worldTextureCoord = lookupWorldTextureCoord();

	for (int i = 0; i < 1.0/inverseAntTextureSize.x; i++) {
		vec3 antTextureCoordinate = (vec3(i, 0, 0) + 0.5) * inverseAntTextureSize;

		vec4 antCellColor = texture(antTexture, antTextureCoordinate);

		highp uint antState = getAntStateFromColor(antCellColor);

		vec3 antPosition = getAntPositionInWorldFromColor(antCellColor);

		float antDistance = getDistanceBetweenLocations(antPosition, worldVolumeCoord);

		if (antDistance < 1) {
			// ant is right on this location
			worldCellColor.a = 1.0;	// add ant to voxel
			
			worldCellColor.b = clamp(worldCellColor.b + 1.0, 0, 1);	// turn trail up to full strength

			worldCellColor.g -= foodPickupRate;	// assume ant has picked up some food

			gl_FragColor = worldCellColor;
			return;
		} else if (antDistance < 2) {
			worldCellColor.b = clamp(worldCellColor.b + 0.1, 0, 1);
		}
	}

	// dissipate trail
	worldCellColor.b -= trailDissipationPerFrame;

	gl_FragColor = worldCellColor;
}

void main()
{
	if (initialized == 0) {
		init();
	} else {
		update();
	}
}
#version 330

#extension GL_EXT_geometry_shader4 : enable 
#extension GL_EXT_gpu_shader4 : enable 

uniform int initialized;

uniform float randomSeed;

uniform sampler3D worldTexture;
uniform sampler3D antTexture;

uniform vec3 inverseWorldTextureSize;
uniform vec3 inverseAntTextureSize;

uniform float foodPickupRate;
uniform float freeWillThreshold;
uniform float foodNestScoreMultiplier;
uniform float trailScoreMultiplier;

in float volumeLayer;

const int NUM_DIMENSIONS = 3;
const int MAX_NUM_NEIGHBORS = 27;

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

float getRandBetween(float low, float high, float seed) {
	return mix(low,high,rand(vec2(seed,seed+1)));
}

vec3 getAntPositionInWorldFromColor(vec4 antCellColor) {
	return (antCellColor.rgb / inverseWorldTextureSize) - 0.5;
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

ivec3 getAntDirectionFromState(highp uint antState) {
	ivec3 direction = ivec3(0, 0, 0);

	if ((antState & BITMASK_X_POS) > 0u) {
		direction.x = 1;
	} else if ((antState & BITMASK_X_NEG) > 0u) {
		direction.x = -1;
	}

	if ((antState & BITMASK_Y_POS) > 0u) {
		direction.y = 1;
	} else if ((antState & BITMASK_Y_NEG) > 0u) {
		direction.y = -1;
	}

	if ((antState & BITMASK_Z_POS) > 0u) {
		direction.z = 1;
	} else if ((antState & BITMASK_Z_NEG) > 0u) {
		direction.z = -1;
	}

	return direction;
}

vec4 getAntCellColorFromAntPositionInWorldAndState(vec3 antPositionInWorld, highp uint antState) {
	// antPositionInWorld is in values [0,1,2,...,15]
	vec3 antPositionInWorldTexture = inverseWorldTextureSize * (antPositionInWorld + 0.5);  // in values [0.5/16,1.5/16,2.5/16,...,15.5/16]
	
	float antStateAlpha = float(antState);

	vec4 updatedAntCellColor = vec4(antPositionInWorldTexture, antStateAlpha);

	return updatedAntCellColor;
}

vec4 lookupWorldCellColorAtCoordinate(vec3 worldVolumeCoord) {
	// this represents where to look in the world texture to find this world voxel
	vec3 worldTextureCoord = inverseWorldTextureSize*(worldVolumeCoord+0.5); // in values [0.5/16,1.5/16,2.5/16,...,15.5/16]

	// this represents the current world state at this voxel
	vec4 worldCellColor = texture(worldTexture, worldTextureCoord);

	return worldCellColor;
}

vec4 lookupAntCellColorInTexture() {
	// this represents which ant we're talking about
	vec3 antVolumeCoord = vec3(gl_FragCoord.xy, volumeLayer) - 0.5;		// in values [0,1,2,...,15]

	// this represents the location in the ant texture to find this ant's current state
	vec3 antTextureCoord = inverseAntTextureSize*(antVolumeCoord+0.5); // in values [0.5/16,1.5/16,2.5/16,...,15.5/16]

	// this represents the ant's current state
	vec4 antCellColor = texture(antTexture, antTextureCoord);

	return antCellColor;
}

float getSeed() {
	// based on combo of frag coord and current color
	float fragCoordSeed = rand((gl_FragCoord.xyz * inverseAntTextureSize).xx);

	return rand(vec2(randomSeed, gl_FragCoord.x*inverseAntTextureSize.x));
}

ivec2[NUM_DIMENSIONS] getValidMovementRangesBasedOnDirectionVector(ivec3 d) {
	// d is in form (-1,-1,-1) to (1,1,1)

	int numZeroDirections = ((d.x == 0) ? 1 : 0) + ((d.y == 0) ? 1 : 0) + ((d.z == 0) ? 1 : 0);
	if (numZeroDirections == 0) {
		// pointing towards corner of XYZ cube

		// range should be in form (-1, 0) or (0, 1) for each axis, depending on the initial direction
		return ivec2[NUM_DIMENSIONS](
			ivec2(min(d.x, 0), max(d.x, 0)),
			ivec2(min(d.y, 0), max(d.y, 0)),
			ivec2(min(d.z, 0), max(d.z, 0))
		);

	} else if (numZeroDirections == 1 || numZeroDirections == 2) {
		// pointing toward edge of XYZ cube (if 1 0-direction)
		// or pointing toward face of XYZ cube (if 2 0-directions)

		// if 0 direction in an axis, it's unconstrained, otherwise it is

		return ivec2[NUM_DIMENSIONS](
			(d.x == 0) ? ivec2(-1,1) : ivec2(min(d.x, 0), max(d.x, 0)),
			(d.y == 0) ? ivec2(-1,1) : ivec2(min(d.y, 0), max(d.y, 0)),
			(d.z == 0) ? ivec2(-1,1) : ivec2(min(d.z, 0), max(d.z, 0))
		);

	} else {
		// direction is zero vector, assume can move in any direction
		return ivec2[NUM_DIMENSIONS](ivec2(-1,1),ivec2(-1,1),ivec2(-1,1));
	}
}

highp uint generateAntState(ivec3 displacement, bool hasFood) {
	highp uint antState = 0u;	// initial -- all flags are zero

	if (hasFood) {
		antState = antState | BITMASK_HAS_FOOD;
	}

	if (displacement.x > 0) {
		antState = antState | BITMASK_X_POS;
	} else if (displacement.x < 0) {
		antState = antState | BITMASK_X_NEG;
	}

	if (displacement.y > 0) {
		antState = antState | BITMASK_Y_POS;
	} else if (displacement.y < 0) {
		antState = antState | BITMASK_Y_NEG;
	}

	if (displacement.z > 0) {
		antState = antState | BITMASK_Z_POS;
	} else if (displacement.z < 0) {
		antState = antState | BITMASK_Z_NEG;
	}

	return antState;
}

bool worldCellContainsNest(vec4 worldCellColor) {
	return (worldCellColor.r > 0);
}

bool worldCellContainsFood(vec4 worldCellColor) {
	return (worldCellColor.g > 0);
}

ivec3 reverseAntDirection(ivec3 antDirection) {
	return -antDirection;
}

ivec3 getDisplacementToStrongestTrailInFront(highp uint antState, vec3 antPositionInWorld, ivec2 minMaxX, ivec2 minMaxY, ivec2 minMaxZ) {
	float seed = getSeed();

	ivec3[MAX_NUM_NEIGHBORS] displacementCandidates;
	float[MAX_NUM_NEIGHBORS] scoresForEachDisplacementCandidate;
	int displacementCandidatesIndex;

	for (displacementCandidatesIndex = 0; displacementCandidatesIndex < MAX_NUM_NEIGHBORS; displacementCandidatesIndex++) {
		scoresForEachDisplacementCandidate[displacementCandidatesIndex] = -1000;
		displacementCandidates[displacementCandidatesIndex] = ivec3(0,0,0);
	}

	float thresholdToNotChooseRandomly = 0.9;

	bool hasFood = getHasFoodFromState(antState);
	
	// go through each possible cell in front of the ant and see which one has the strongest trail
	int i, j, k;
	for (i = minMaxX.s; i <= minMaxX.t; i++) {
		for (j = minMaxY.s; j <= minMaxY.t; j++) {
			for (k = minMaxZ.s; k <= minMaxZ.t; k++) {
				if (i != 0 || j != 0 || k != 0) {	// don't evaluate any spot where we don't move
					vec4 worldCellColor = lookupWorldCellColorAtCoordinate(antPositionInWorld + ivec3(i,j,k));

					float totalScoreAtThisCell = 0.0;

					float trailScoreAtThisCell = worldCellColor.b * trailScoreMultiplier;
					float foodScoreAtThisCell = worldCellColor.g * foodNestScoreMultiplier;
					float nestScoreAtThisCell = worldCellColor.r * foodNestScoreMultiplier;

					if (foodScoreAtThisCell > 0.0 && hasFood) {
						// we don't want to go to a cell that has food if we already have food
						foodScoreAtThisCell = -1000;
					}

					if (nestScoreAtThisCell > 0.0 && !hasFood) {
						// we don't want to go to a cell that has the nest when we are empty-handed
						nestScoreAtThisCell = -1000;
					}

					totalScoreAtThisCell = trailScoreAtThisCell + foodScoreAtThisCell + nestScoreAtThisCell;
					scoresForEachDisplacementCandidate[displacementCandidatesIndex] = totalScoreAtThisCell;
					displacementCandidates[displacementCandidatesIndex] = ivec3(i,j,k);
				}

				displacementCandidatesIndex++;
			}
		}
	}
	
	float highestScore = 0.0;
	ivec3 currentDisplacementCandidate = ivec3(0,0,0);

	for (displacementCandidatesIndex = 0; displacementCandidatesIndex < MAX_NUM_NEIGHBORS; displacementCandidatesIndex++) {
		if (highestScore < scoresForEachDisplacementCandidate[displacementCandidatesIndex]) {
			highestScore = scoresForEachDisplacementCandidate[displacementCandidatesIndex];
			currentDisplacementCandidate = displacementCandidates[displacementCandidatesIndex];
		}
	}

	float strengthOfFreeWill = getRandBetween(0, 1, ++seed);
	
	if (highestScore <= thresholdToNotChooseRandomly || strengthOfFreeWill >= freeWillThreshold) {
		// no strong trail in front, just return some random displacement
		currentDisplacementCandidate = ivec3(
			round(getRandBetween(minMaxX.s, minMaxX.t, ++seed)),
			round(getRandBetween(minMaxY.s, minMaxY.t, ++seed)),
			round(getRandBetween(minMaxZ.s, minMaxZ.t, ++seed))
		);
	}

	return currentDisplacementCandidate;
}

ivec3 handleEdgeBoundaries(const ivec3 initialAntDirection, const vec3 antPositionInWorld) {
	ivec3 outputAntDirection = initialAntDirection;

	float minX = 0;
	float maxX = 1.0/inverseWorldTextureSize.x - 1;
	float minY = 0;
	float maxY = 1.0/inverseWorldTextureSize.y - 1;
	float minZ = 0;
	float maxZ = 1.0/inverseWorldTextureSize.z - 1;

	if (antPositionInWorld.x + initialAntDirection.x < minX) {
		outputAntDirection.x = 1;
	}

	if (antPositionInWorld.x + initialAntDirection.x > maxX) {
		outputAntDirection.x = -1;
	}

	if (antPositionInWorld.y + initialAntDirection.y < minY) {
		outputAntDirection.y = 1;
	}

	if (antPositionInWorld.y + initialAntDirection.y > maxY) {
		outputAntDirection.y = -1;
	}

	if (antPositionInWorld.z + initialAntDirection.z < minZ) {
		outputAntDirection.z = 1;
	}

	if (antPositionInWorld.z + initialAntDirection.z > maxZ) {
		outputAntDirection.z = -1;
	}

	return outputAntDirection;
}

vec4 moveAnt(vec4 antCellColor) {
	float seed = getSeed();

	vec3 antPositionInWorld = getAntPositionInWorldFromColor(antCellColor); // in values [0,1,2,...,15]
	highp uint antState = getAntStateFromColor(antCellColor);

	bool hasFood = getHasFoodFromState(antState);
	ivec3 antDirection = getAntDirectionFromState(antState);

	// get the state of the world where the ant is
	vec4 worldCellColor = lookupWorldCellColorAtCoordinate(antPositionInWorld);

	ivec3 antDirectionAfterEdgeHandling = handleEdgeBoundaries(antDirection, antPositionInWorld);

	if (antDirectionAfterEdgeHandling != antDirection) {
		antDirection = antDirectionAfterEdgeHandling;
	} else if (worldCellContainsNest(worldCellColor) && hasFood) {
		// drop any food that is carried
		hasFood = false;

		// turn around
		antDirection = reverseAntDirection(antDirection);
	} else if (worldCellContainsFood(worldCellColor) && !hasFood) {
		// pick up some food here
		hasFood = true;

		// turn around
		antDirection = reverseAntDirection(antDirection);
	}

	ivec2[NUM_DIMENSIONS] validMinMaxes = getValidMovementRangesBasedOnDirectionVector(antDirection);

	ivec3 displacement = getDisplacementToStrongestTrailInFront(antState, antPositionInWorld, validMinMaxes[0], validMinMaxes[1], validMinMaxes[2]);

	antPositionInWorld += displacement;

	antState = generateAntState(displacement, hasFood);

	vec4 updatedAntCellColor = getAntCellColorFromAntPositionInWorldAndState(antPositionInWorld, antState);

	return updatedAntCellColor;
}


void init()
{
	float seed = getSeed();

	// this represents the XYZ placement of this ant in the world

	vec3 centerOfWorld = 1.0 / inverseWorldTextureSize / 2.0;	// if texture size is 16x16x16, this gets element 8,8,8

	vec3 initialAntPositionInWorld = centerOfWorld;

	bool hasFood = false;

	ivec3 initialAntDirection = ivec3(
		round(getRandBetween(-1, 1, ++seed)),
		round(getRandBetween(-1, 1, ++seed)),
		round(getRandBetween(-1, 1, ++seed))
	);

	highp uint initialAntState = generateAntState(initialAntDirection, hasFood);

	gl_FragColor = getAntCellColorFromAntPositionInWorldAndState(initialAntPositionInWorld, initialAntState);
}

void update()
{
	vec4 antCellColor = lookupAntCellColorInTexture();
	
	antCellColor = moveAnt(antCellColor);

	gl_FragColor = antCellColor;
}

void main()
{
	if (initialized == 0) {
		init();
	} else {
		update();
	}

}
#pragma once

#define GLEW_STATIC 1
#include <GL/glew.h>
#include <GL/glut.h>
#include <string>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include "Utils.h"
#include "MarchingCubesConstants.h"
#include <time.h>

class AntSim
{

public:
	AntSim(int w, int h);

	void restart();
	void update();
	void display();
	
	float* view_rotate();

	float updateIntervalSeconds;	// number of ms to wait between simulation updates
	float trailOpacity;	// how opaque to show the trails in the visualization
	float cameraDistance; // how far away to have the camera
	float trailDissipationPerFrame;	// how much a trail fades each time the simulation updates

	float foodNestScoreMultiplier;	// how much importance to place on food or nest when choosing where to move ant
	float trailScoreMultiplier;	// how much importance to place on trail when choosing where to move ant

	int width;	// width of the screen
	int height;	// height of the screen

	int numAnts;
	int cubeLength;

	bool simulationRunning;

	float randomMovementProbability;	// between 0 and 1, probability that ant will choose to move randomly rather than selecting the cell with highest score

private:		
	int _initialized;		// if the cells are initialized (=1) or not (=0)

	GLuint _initializedLoc;
    GLuint _texUnitLoc;
    
	//----------------

	GLuint _visualizationProgramId;	// program used for drawing the volume to the screen

	glm::ivec3 _worldSize;	// the size of the ant world
	glm::vec3 _voxelSize;	// how big in each dimension a voxel should be

	GLuint _worldTextureId;

	float _view_rotate[16];

	GLuint _simulationWorldProgramId;
	GLuint _simulationAntProgramId;

	void updateSimulation(GLuint simulationShaderProgramId, PingPong *pingPong, GLuint activeTextureUnit, PingPong *supportPingPong, GLuint supportTextureUnit);

	void updateWorld();
	void updateAnts();

	GLuint _quadVbo;

	PingPong _worldPingPong;
	
	PingPong _antPingPong;

	
	float _foodPickupRate;	// when an ant picks up some food, how much does that diminish the food supply of a cell

	float _initialFoodRatio;	// amount of food to put in world; e.g. 0.2 = 20% of tiles have food

	

	clock_t _lastUpdateTime;
};


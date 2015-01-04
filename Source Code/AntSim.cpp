#include "AntSim.h"
#include "Utils.h"
#include <iostream>
#include <fstream>
#include <time.h>

extern int triangleTable[256][16];

AntSim::AntSim(int w, int h) : _initialized(0), width(w), height(h)
{
	// set adjustable controls (don't want them resetting when restarting)
	updateIntervalSeconds = 0.01f;
	trailOpacity = 0.5f;
	cameraDistance = 3.0f;
	numAnts = 4;
	cubeLength = 32;
	randomMovementProbability = 0.1;
	trailDissipationPerFrame = 0.001;
	_initialFoodRatio = 0.005;
	foodNestScoreMultiplier = 10.0;
	trailScoreMultiplier = 1.0;

	simulationRunning = true;

	_quadVbo = Utils::initializeQuadVBO();

	glEnable(GL_TEXTURE_3D);

	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glEnableVertexAttribArray(SlotPosition);

	printf("setting up world with size %dx%dx%d\n", cubeLength, cubeLength, cubeLength);
	_worldSize = glm::ivec3(cubeLength, cubeLength, cubeLength);
	_voxelSize = glm::vec3(2.0f/_worldSize.x, 2.0f/_worldSize.y, 2.0f/_worldSize.z);

	_worldPingPong = Utils::createPingPong(_worldSize);

	_antPingPong = Utils::createPingPong(glm::ivec3(numAnts, 1, 1));

	_visualizationProgramId = glCreateProgram();
	Utils::initializeShader(_visualizationProgramId, "visualization_vertex.glsl", GL_VERTEX_SHADER);
	Utils::initializeShader(_visualizationProgramId, "visualization_geometry.glsl", GL_GEOMETRY_SHADER);
	Utils::initializeShader(_visualizationProgramId, "visualization_fragment.glsl", GL_FRAGMENT_SHADER);

	glLinkProgram(_visualizationProgramId);

	Utils::logProgramLinkError(_visualizationProgramId);

	glUseProgram(_visualizationProgramId);

	printf("assigning samplers to textures\n");

	glUniform1i(glGetUniformLocation(_visualizationProgramId, "worldTexture"), 0);
	glUniform1i(glGetUniformLocation(_visualizationProgramId, "antTexture"), 1);

	printf("set up triangle table texture for marching cubes...\n");

	GLuint triangleTableTexture;
	glGenTextures(1, &triangleTableTexture);
	glActiveTexture(GL_TEXTURE2);
	glEnable(GL_TEXTURE_2D);

	glBindTexture(GL_TEXTURE_2D, triangleTableTexture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

	glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA16I_EXT, 16, 256, 0, GL_ALPHA_INTEGER_EXT, GL_INT, &triangleTable);

	glUniform1i(glGetUniformLocation(_visualizationProgramId, "triangleTableTexture"), 2);

	glValidateProgram(_visualizationProgramId);

	Utils::logProgramValidationError(_visualizationProgramId);

	printf("assigning initial uniforms\n");

	printf("any errors? %s\n", gluErrorString(glGetError()));

	printf("now to initialize the simulation\n");

	_simulationWorldProgramId = Utils::createSimulationProgram("simulation_vertex.glsl", "simulation_geometry.glsl", "simulation_world_fragment.glsl");
	printf("_simulationWorldProgramId: %d\n", _simulationWorldProgramId);

	_simulationAntProgramId = Utils::createSimulationProgram("simulation_vertex.glsl", "simulation_geometry.glsl", "simulation_ant_fragment.glsl");
	printf("_simulationAntProgramId: %d\n", _simulationAntProgramId);

	restart();
}

float* AntSim::view_rotate()
{
	return _view_rotate;
}

void AntSim::restart()
{
	srand (static_cast <unsigned> (time(0)));

	_lastUpdateTime = 0;

	_view_rotate[0] = 1;
	_view_rotate[1] = 0;
	_view_rotate[2] = 0;
	_view_rotate[3] = 0;

	_view_rotate[4] = 0;
	_view_rotate[5] = 1;
	_view_rotate[6] = 0;
	_view_rotate[7] = 0;

	_view_rotate[8] = 0;
	_view_rotate[9] = 0;
	_view_rotate[10] = 1;
	_view_rotate[11] = 0;

	_view_rotate[12] = 0;
	_view_rotate[13] = 0;
	_view_rotate[14] = 0;
	_view_rotate[15] = 1;

	_foodPickupRate = 0.5; // setting this to 1.0 will make the food immediately disappear, but this is bad for swarm behavior
	
	simulationRunning = false;

	_initialized = 0;

	_worldSize = glm::ivec3(cubeLength, cubeLength, cubeLength);
	_voxelSize = glm::vec3(2.0f/_worldSize.x, 2.0f/_worldSize.y, 2.0f/_worldSize.z);

	_worldPingPong = Utils::updatePingPongSize(_worldPingPong, glm::ivec3(_worldSize.x, _worldSize.y, _worldSize.z));
	_antPingPong = Utils::updatePingPongSize(_antPingPong, glm::ivec3(numAnts, 1, 1));

	glUseProgram(_visualizationProgramId);

	glUniform3f(glGetUniformLocation(_visualizationProgramId, "voxelSize"), _voxelSize.x, _voxelSize.y, _voxelSize.z);

	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[0]"), 0.0f,			0.0f,			0.0f);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[1]"), _voxelSize.x,	0.0f,			0.0f);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[2]"), _voxelSize.x,	_voxelSize.y,	0.0f);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[3]"), 0.0f,			_voxelSize.y,	0.0f);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[4]"), 0.0f,			0.0f,			_voxelSize.z);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[5]"), _voxelSize.x,	0.0f,			_voxelSize.z);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[6]"), _voxelSize.x,	_voxelSize.y,	_voxelSize.z);
	glUniform3f(glGetUniformLocation(_visualizationProgramId, "cubeVertexDecals[7]"), 0.0f,			_voxelSize.y,	_voxelSize.z);

	simulationRunning = true;
}

void AntSim::updateWorld() {
	updateSimulation(_simulationWorldProgramId, &_worldPingPong, GL_TEXTURE0, &_antPingPong, GL_TEXTURE1);
}

void AntSim::updateAnts() {
	updateSimulation(_simulationAntProgramId, &_antPingPong, GL_TEXTURE1, &_worldPingPong, GL_TEXTURE0);
}

void AntSim::updateSimulation(GLuint simulationShaderProgramId, PingPong *pingPong, GLuint activeTextureUnit, PingPong *supportPingPong, GLuint supportTextureUnit) {
	glBindBuffer(GL_ARRAY_BUFFER, _quadVbo);
	glVertexAttribPointer(SlotPosition, 2, GL_SHORT, GL_FALSE, 2 * sizeof(short), 0);
	glViewport(0, 0, pingPong->current.volumeSize.x, pingPong->current.volumeSize.y);

	glUseProgram(simulationShaderProgramId);

	// set uniforms here...

	float r = static_cast <float> (rand()) / static_cast <float> (RAND_MAX);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "randomSeed"), r);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "initialFoodRatio"), _initialFoodRatio);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "trailDissipationPerFrame"), trailDissipationPerFrame);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "freeWillThreshold"), 1.0 - randomMovementProbability);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "foodNestScoreMultiplier"), foodNestScoreMultiplier);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "trailScoreMultiplier"), trailScoreMultiplier);
	glUniform1f(glGetUniformLocation(simulationShaderProgramId, "foodPickupRate"), _foodPickupRate);
	glUniform1i(glGetUniformLocation(simulationShaderProgramId, "initialized"), _initialized);
	glUniform1i(glGetUniformLocation(simulationShaderProgramId, "worldTexture"), 0);	// set to GL_TEXTURE0
	glUniform1i(glGetUniformLocation(simulationShaderProgramId, "antTexture"), 1);	// set to GL_TEXTURE1
	glUniform3f(glGetUniformLocation(simulationShaderProgramId, "inverseWorldTextureSize"), 
		1.0f / _worldPingPong.current.volumeSize.x,
		1.0f / _worldPingPong.current.volumeSize.y,
		1.0f / _worldPingPong.current.volumeSize.z);
	glUniform3f(glGetUniformLocation(simulationShaderProgramId, "inverseAntTextureSize"), 
		1.0f / _antPingPong.current.volumeSize.x,
		1.0f / _antPingPong.current.volumeSize.y,
		1.0f / _antPingPong.current.volumeSize.z);

	// bind textures

	glBindFramebuffer(GL_FRAMEBUFFER, pingPong->current.fboId);

	// note: we have both the active and support texture units here, because each shader program requires not only its own texture, but the other one too
	// e.g. the world needs to read from ant, ant needs to read from world
	
	glActiveTexture(supportTextureUnit);
	glBindTexture(GL_TEXTURE_3D, supportPingPong->previous.textureId);


	glActiveTexture(activeTextureUnit);
	glBindTexture(GL_TEXTURE_3D, pingPong->previous.textureId);

	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ZERO);
	glBlendEquation(GL_FUNC_ADD);

	glDisable(GL_CULL_FACE);

	glClearColor(0.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	// draw arrays instanced

	glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, pingPong->current.volumeSize.z);

	Utils::swapPingPong(pingPong);

	glActiveTexture(activeTextureUnit);
	glBindTexture(GL_TEXTURE_3D, 0);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);

	glUseProgram(0);
}

void AntSim::update()
{
	if (simulationRunning) {
		clock_t currentClock = clock();
		clock_t elapsedTime = currentClock - _lastUpdateTime;
		float secondsSinceUpdate = (float)elapsedTime / CLOCKS_PER_SEC;
		if (_initialized != 1 || secondsSinceUpdate >= updateIntervalSeconds) {
			updateAnts();
			updateWorld();

			_initialized = 1;

			_lastUpdateTime = currentClock;
		}
	}
}

void AntSim::display()
{
	if (simulationRunning) {
		glBindFramebuffer(GL_FRAMEBUFFER, 0);

		glViewport(0, 0, width, height);
		glDepthMask(GL_TRUE);
		glClearColor(1.0, 1.0, 1.0, 1.0);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		glEnable(GL_DEPTH_TEST);
		glDisable(GL_STENCIL_TEST);
		glDisable(GL_ALPHA_TEST);
	
		glEnable( GL_BLEND );
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		glBlendEquation(GL_FUNC_ADD);
	
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
		glPushMatrix();

		glTranslatef(0, 0, -cameraDistance);

		glMultMatrixf(_view_rotate);

		glActiveTexture(GL_TEXTURE0);
		glBindTexture(GL_TEXTURE_3D, _worldPingPong.current.textureId);
	
		glActiveTexture(GL_TEXTURE1);
		glBindTexture(GL_TEXTURE_3D, _antPingPong.current.textureId);

		glUseProgram(_visualizationProgramId);

		// change any uniforms here if neded

		glUniform1i(glGetUniformLocation(_visualizationProgramId, "worldTexture"), 0);	// set to GL_TEXTURE0
		glUniform1i(glGetUniformLocation(_visualizationProgramId, "antTexture"), 1);	// set to GL_TEXTURE1
		glUniform1f(glGetUniformLocation(_visualizationProgramId, "trailOpacity"), trailOpacity);

		glUniform3f(glGetUniformLocation(_visualizationProgramId, "inverseWorldTextureSize"), 
			1.0f / _worldPingPong.current.volumeSize.x,
			1.0f / _worldPingPong.current.volumeSize.y,
			1.0f / _worldPingPong.current.volumeSize.z);

		glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

		glBegin(GL_POINTS);

		bool cameraAtPositiveX = (_view_rotate[8] >= 0.0f);
		bool cameraAtPositiveY = (_view_rotate[9] >= 0.0f);
		bool cameraAtPositiveZ = (_view_rotate[10] >= 0.0f);

		bool shouldNotAdjustDrawOrder = true;

		/*
		if (shouldNotAdjustDrawOrder && cameraAtPositiveZ) {
			// camera is in front of the cube

			for(float k = -1; k < 1.0f; k += _voxelSize.z) {
				for(float j = -1; j < 1.0f; j += _voxelSize.y) {
					for(float i = -1; i < 1.0f; i += _voxelSize.x) {
						glVertex3f(i, j, k);	
					}
				}
			}
		} else {
			// camera is behind the cube

			for(float k = 1-_voxelSize.z; k >= -1.0f; k -= _voxelSize.z) {
				for(float j = 1-_voxelSize.y; j >= -1.0f; j -= _voxelSize.y) {
					for(float i = 1-_voxelSize.x; i >= -1.0f; i -= _voxelSize.x) {
						glVertex3f(i, j, k);	
					}
				}
			}
		}
		*/

		for(float k = -1; k < 1.0f; k += _voxelSize.z) {
				for(float j = -1; j < 1.0f; j += _voxelSize.y) {
					for(float i = -1; i < 1.0f; i += _voxelSize.x) {
						glVertex3f(i, j, k);	
					}
				}
			}

		glEnd();


		glUseProgram(0);

		glPopMatrix();
	
	}
	
}
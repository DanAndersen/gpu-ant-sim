#pragma once

#define GLEW_STATIC 1
#include <GL/glew.h>
#include <GL/glut.h>
#include <string>
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

struct Volume {
	GLuint fboId;
	GLuint textureId;
	glm::ivec3 volumeSize;
};

struct PingPong {
	Volume previous;
	Volume current;
};

enum AttributeSlot {
	SlotPosition
};

class Utils
{
public:
	static GLuint initializeShader(GLuint programId, char* filename, GLuint shaderType);
	static GLint logProgramLinkError(GLuint programId);
	static GLint logProgramValidationError(GLuint programId);

	static GLuint initializeQuadVBO();

	static Volume createVolume(glm::ivec3 volumeSize);

	static void doOpenGLErrorCheck(bool success, char * errorMessage);

	static GLuint createSimulationProgram(char * vsFile, char * gsFile, char * fsFile);

	static void swapPingPong(PingPong* pingPong);

	static PingPong createPingPong(glm::ivec3 volumeSize);

	static PingPong updatePingPongSize(PingPong pingPong, glm::ivec3 volumeSize);

private:
	static int loadShaderSource(char* filename, std::string& text);

	static void updateTextureSize(GLuint textureId, glm::ivec3 volumeSize);

};


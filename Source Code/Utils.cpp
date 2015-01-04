#include "Utils.h"
#include <iostream>
#include <fstream>

int Utils::loadShaderSource(char* filename, std::string& text)
{
	std::ifstream ifs;
	ifs.open(filename, std::ios::in);

	std::string line;
	while (ifs.good()) {
        getline(ifs, line);

		text += line + "\n";
    }

	return 0;
}

GLint Utils::logProgramLinkError(GLuint programId)
{
	GLint success;
	glGetProgramiv(programId, GL_LINK_STATUS, &success);
	if (success == GL_FALSE) {

		GLint maxLength = 0;
		glGetProgramiv(programId, GL_INFO_LOG_LENGTH, &maxLength);

		char *log = new char[maxLength];

		glGetProgramInfoLog(programId, maxLength, &maxLength, log);

		glDeleteProgram(programId);

		printf("Link error: %s\n", log);
	}
	return success;
}

GLint Utils::logProgramValidationError(GLuint programId)
{
	GLint success;
	glGetProgramiv(programId, GL_VALIDATE_STATUS, &success);
	if (success == GL_FALSE) {

		GLint maxLength = 0;
		glGetProgramiv(programId, GL_INFO_LOG_LENGTH, &maxLength);

		char *log = new char[maxLength];

		glGetProgramInfoLog(programId, maxLength, &maxLength, log);

		glDeleteProgram(programId);

		printf("Validation error: %s\n", log);
	}
	return success;
}

GLuint Utils::initializeShader(GLuint programId, char* filename, GLuint shaderType) 
{
	std::string shaderSource;
	Utils::loadShaderSource(filename, shaderSource);

	GLuint shader = glCreateShader(shaderType);
	const char* source = shaderSource.c_str();
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

	GLint success = 0;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
	if(success == GL_FALSE)
	{
		GLint maxLength = 0;
		glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &maxLength);
 
		char *log = new char[maxLength];

		glGetShaderInfoLog(shader, maxLength, &maxLength, log);
 
		printf("Compilation error: %s\n", log);

		glDeleteShader(shader);
 	}

    glAttachShader(programId, shader);

	printf("initialized shader %s, errors: %s\n", filename, gluErrorString(glGetError()));

	return shader;
}

GLuint Utils::initializeQuadVBO() 
{
	short verts[] = {
		-1, -1,
		1, -1,
		-1, 1, 
		1, 1
	};
	GLuint vbo;
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
	return vbo;
}

void Utils::doOpenGLErrorCheck(bool success, char * errorMessage)
{
	if (!success) {
		printf("%s\n", errorMessage);
	}
}

void Utils::updateTextureSize(GLuint textureId, glm::ivec3 volumeSize) {
	glBindTexture(GL_TEXTURE_3D, textureId);

	glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA32F, volumeSize.x, volumeSize.y, volumeSize.z, 0, GL_RGBA, GL_FLOAT, 0);

	doOpenGLErrorCheck(glGetError() == GL_NO_ERROR, "volume texture creation failed");
}

PingPong Utils::updatePingPongSize(PingPong pingPong, glm::ivec3 volumeSize) {
	updateTextureSize(pingPong.previous.textureId, volumeSize);
	pingPong.previous.volumeSize = volumeSize;
	
	updateTextureSize(pingPong.current.textureId, volumeSize);
	pingPong.current.volumeSize = volumeSize;

	printf("updated texture size to %d x %d x %d\n", volumeSize.x, volumeSize.y, volumeSize.z);

	return pingPong;
}

Volume Utils::createVolume(glm::ivec3 volumeSize) 
{
	printf("creating volume of size %d x %d x %d\n", volumeSize.x, volumeSize.y, volumeSize.z);

	printf("creating FBO\n");

	GLuint fboId;
	glGenFramebuffers(1, &fboId);
	glBindFramebuffer(GL_FRAMEBUFFER, fboId);

	printf("creating texture for volume\n");
	
	GLuint textureId;
	glGenTextures(1, &textureId);

	updateTextureSize(textureId, volumeSize);

	printf("creating render buffer\n");

	GLuint renderBufferId;
	glGenRenderbuffers(1, &renderBufferId);
	glBindRenderbuffer(GL_RENDERBUFFER, renderBufferId);
	glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, renderBufferId, 0);

	doOpenGLErrorCheck(glGetError() == GL_NO_ERROR, "attaching render buffer failed");

	doOpenGLErrorCheck(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "failed to create FBO");

	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

	glClear(GL_COLOR_BUFFER_BIT);

	glBindFramebuffer(GL_FRAMEBUFFER, 0);

	Volume volume = { fboId, textureId, volumeSize };

	return volume;
}

PingPong Utils::createPingPong(glm::ivec3 volumeSize) 
{
	PingPong pingPong = { createVolume(volumeSize), createVolume(volumeSize) };
	return pingPong;
}

void Utils::swapPingPong(PingPong* pingPong) {
	Volume temp = pingPong->current;
	pingPong->current = pingPong->previous;
	pingPong->previous = temp;
}

GLuint Utils::createSimulationProgram(char * vsFile, char * gsFile, char * fsFile)
{
	GLuint simulationProgramId = glCreateProgram();

	Utils::initializeShader(simulationProgramId, vsFile, GL_VERTEX_SHADER);
	Utils::initializeShader(simulationProgramId, gsFile, GL_GEOMETRY_SHADER);
	Utils::initializeShader(simulationProgramId, fsFile, GL_FRAGMENT_SHADER);

	glBindAttribLocation(simulationProgramId, SlotPosition, "Position");

	glLinkProgram(simulationProgramId);

	Utils::logProgramLinkError(simulationProgramId);

	glValidateProgram(simulationProgramId);

	Utils::logProgramValidationError(simulationProgramId);

	return simulationProgramId;
}
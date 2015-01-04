#ifdef _WIN32
#include <windows.h>
#endif

#define GLEW_STATIC 1
#include <GL/glew.h>
#include <stdio.h>
#include <GL/glut.h>
#include <GL/glui.h>
#include "AntSim.h"
#include <glm/gtc/type_ptr.hpp>


static int winWidth = 800;
static int winHeight = 600;
static int winId = -1;
static GLUI *glui;

AntSim *antsim;

const int NUM_SUPPORTED_CUBE_LENGTHS = 3;
int SUPPORTED_CUBE_LENGTHS[NUM_SUPPORTED_CUBE_LENGTHS] = {32, 64, 128};
int selectedCubeLengthButton = 0;

/*****************************************************************************
*****************************************************************************/
static void
leftButtonDownCB(void)
{
}

/*****************************************************************************
*****************************************************************************/
static void
leftButtonUpCB(void)
{
}

/*****************************************************************************
*****************************************************************************/
static void
middleButtonDownCB(void)
{
}


/*****************************************************************************
*****************************************************************************/
static void
middleButtonUpCB(void)
{
}

/*****************************************************************************
*****************************************************************************/
static void
rightButtonDownCB(void)
{
}


/*****************************************************************************
*****************************************************************************/
static void
rightButtonUpCB(void)
{
}

/*****************************************************************************
*****************************************************************************/
static void
mouseCB(int button, int state, int x, int y)
{
   if (button == GLUT_LEFT_BUTTON && state == GLUT_DOWN)
      leftButtonDownCB();
   else if (button == GLUT_LEFT_BUTTON && state == GLUT_UP)
      leftButtonUpCB();
   else if (button == GLUT_MIDDLE_BUTTON && state == GLUT_DOWN)
      middleButtonDownCB();
   else if (button == GLUT_MIDDLE_BUTTON && state == GLUT_UP)
      middleButtonUpCB();
   else if (button == GLUT_RIGHT_BUTTON && state == GLUT_DOWN)
      rightButtonDownCB();
   else if (button == GLUT_RIGHT_BUTTON && state == GLUT_UP)
      rightButtonUpCB();
}


/*****************************************************************************
*****************************************************************************/
static void
motionCB(int x, int y)
{
}

void passiveMotionCB(int,int){
}

/*****************************************************************************
*****************************************************************************/
void
reshapeCB(int width, int height)
{
	int tx, ty, tw, th;
	GLUI_Master.get_viewport_area(&tx, &ty, &tw, &th);

    if (th == 0) th = 1;
    
	antsim->width = tw;
	antsim->height = th;

	GLdouble aspect = (GLdouble)tw / (GLdouble)th;

    glViewport(0, 0, tw, th);
    
    glMatrixMode(GL_PROJECTION);    
    glLoadIdentity();               
	gluPerspective(60.0, aspect, 0.001, 1000);
    glMatrixMode(GL_MODELVIEW);     
    glLoadIdentity();   
}

/*****************************************************************************
*****************************************************************************/
void
keyboardCB(unsigned char key, int x, int y)
{
}

/*****************************************************************************
*****************************************************************************/
void
idleFunc()
{		
	if ( glutGetWindow() != winId ) 
	{
		glutSetWindow(winId);  
	}

	GLUI_Master.sync_live_all();  

	glutPostRedisplay();
}


/*****************************************************************************
*****************************************************************************/
void
refreshCB()
{
	if (antsim->simulationRunning) {
		antsim->update();

		antsim->display();

		glutSwapBuffers();
	}
}

/*****************************************************************************
*****************************************************************************/
void initialize()
{
    // Initialize glew library
    glewInit();

    // Create the gpgpu object
    antsim = new AntSim(winWidth, winHeight);
}

void __cdecl onChangeCubeLength(int id) {
	int selectedCubeLength = SUPPORTED_CUBE_LENGTHS[selectedCubeLengthButton];
	printf("selecting cube length: %d\n", selectedCubeLength);
	antsim->cubeLength = selectedCubeLength;
}

void __cdecl restart(int id) {
	printf("restart button pressed\n");
	antsim->restart();
}

/*****************************************************************************
*****************************************************************************/
void MakeGUI()
{
	glui = GLUI_Master.create_glui("Ant Colony Simulation", 0, 0, 0);

	// initialization

	GLUI_Panel *initialization_panel = glui->add_panel("Initialization");

	GLUI_Spinner *simulation_num_ants_spinner = glui->add_spinner_to_panel(initialization_panel, "Number of Ants", GLUI_SPINNER_INT, &antsim->numAnts);
	simulation_num_ants_spinner->set_int_limits(1, 128);

	int CHANGE_CUBE_LENGTH_ID = 0;

	GLUI_Panel *cube_length_panel = glui->add_panel_to_panel(initialization_panel, "World Size");

	GLUI_RadioGroup *simulation_cube_length_radio_group = glui->add_radiogroup_to_panel(cube_length_panel, &selectedCubeLengthButton, CHANGE_CUBE_LENGTH_ID, (GLUI_Update_CB)onChangeCubeLength);
	for (int i = 0; i < NUM_SUPPORTED_CUBE_LENGTHS; i++) {
		std::string cubeLengthLabel = std::to_string(static_cast<long long>(SUPPORTED_CUBE_LENGTHS[i]));
		
		glui->add_radiobutton_to_group(simulation_cube_length_radio_group, cubeLengthLabel.c_str());
	}
	onChangeCubeLength(0);

	int RESTART_ID = 1;

	GLUI_Button *restart_button = glui->add_button_to_panel(initialization_panel, "Restart", RESTART_ID, (GLUI_Update_CB)restart);

	// simulation

	GLUI_Panel *simulation_panel = glui->add_panel("Simulation");

	GLUI_Spinner *simulation_random_movement_probability = glui->add_spinner_to_panel(simulation_panel, "Random Movement Probability", GLUI_SPINNER_FLOAT, &antsim->randomMovementProbability);
	simulation_random_movement_probability->set_float_limits(0.0, 1.0);

	GLUI_Spinner *simulation_food_nest_score_multiplier_spinner = glui->add_spinner_to_panel(simulation_panel, "Food/Nest Score Multiplier (default = 10)", GLUI_SPINNER_FLOAT, &antsim->foodNestScoreMultiplier);
	simulation_food_nest_score_multiplier_spinner->set_float_limits(1, 50);

	GLUI_Spinner *simulation_trail_score_multiplier_spinner = glui->add_spinner_to_panel(simulation_panel, "Trail Score Multiplier (default = 1)", GLUI_SPINNER_FLOAT, &antsim->trailScoreMultiplier);
	simulation_trail_score_multiplier_spinner->set_float_limits(1, 50);

	GLUI_Spinner *simulation_trail_fade_rate_spinner = glui->add_spinner_to_panel(simulation_panel, "Trail Fade Rate", GLUI_SPINNER_FLOAT, &antsim->trailDissipationPerFrame);
	simulation_trail_fade_rate_spinner->set_float_limits(0.0, 1.0);
	simulation_trail_fade_rate_spinner->set_speed(0.01f);


	// visualization panel

	GLUI_Panel *visualization_panel = glui->add_panel("Visualization");

	glui->add_rotation_to_panel(visualization_panel, "Rotation", antsim->view_rotate());

	GLUI_Spinner *visualization_update_rate_spinner = glui->add_spinner_to_panel(visualization_panel, "Update Rate (sec)", GLUI_SPINNER_FLOAT, &antsim->updateIntervalSeconds);
	visualization_update_rate_spinner->set_float_limits(0, 0.1);

	GLUI_Spinner *visualization_trail_opacity_spinner = glui->add_spinner_to_panel(visualization_panel, "Trail Opacity", GLUI_SPINNER_FLOAT, &antsim->trailOpacity);
	visualization_trail_opacity_spinner->set_float_limits(0.0, 1.0);

	GLUI_Spinner *visualization_camera_distance_spinner = glui->add_spinner_to_panel(visualization_panel, "Camera Distance", GLUI_SPINNER_FLOAT, &antsim->cameraDistance);
	visualization_camera_distance_spinner->set_float_limits(0.0, 10.0);
	
	GLUI_Panel *legend_panel = glui->add_panel("Legend");

	glui->add_statictext_to_panel(legend_panel, "Red = nest");
	glui->add_statictext_to_panel(legend_panel, "Green = food (fades as consumed)");
	glui->add_statictext_to_panel(legend_panel, "Blue = pheromone trail (fades over time)");
	glui->add_statictext_to_panel(legend_panel, "White = ant");
	

	glui->set_main_gfx_window(winId);

	/* We register the idle callback with GLUI, *not* with GLUT */
	GLUI_Master.set_glutIdleFunc(idleFunc);
}

/*****************************************************************************
*****************************************************************************/
int
main(int argc, char *argv[])
{
	// init OpenGL/GLUT
	glutInit(&argc, argv);
	
	// create main window
	glutInitWindowPosition(0, 0);
	glutInitWindowSize(winWidth, winHeight);
	glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA);
	winId = glutCreateWindow("Ant Colony Visualization");

	initialize();
	
	// setup callbacks
	glutDisplayFunc(refreshCB);
	GLUI_Master.set_glutReshapeFunc(reshapeCB);
	GLUI_Master.set_glutKeyboardFunc(keyboardCB);
	GLUI_Master.set_glutMouseFunc(mouseCB);
	GLUI_Master.set_glutSpecialFunc( NULL );
	glutMotionFunc(motionCB);
	glutPassiveMotionFunc(passiveMotionCB);

	// force initial matrix setup
	reshapeCB(winWidth, winHeight);

	// set modelview matrix stack to identity
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

	// make GLUI GUI
	MakeGUI();
	glutMainLoop();

	return (TRUE);
}

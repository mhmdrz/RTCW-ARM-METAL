/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

SDL2 OpenGL context / GLimp implementation for the modern macOS (arm64)
port. Replaces the X11/GLX code in unix/linux_glimp.c and the Cocoa code
in macosx/macosx_glimp.m. Uses the qgl_linked.h path (qgl*->gl*), so only
the handful of extension entry points are resolved dynamically here.
===========================================================================
*/

#include <SDL.h>
#include "../renderer/tr_local.h"

// ---- GL extension entry points (declared extern in qgl.h) ----------------
void ( APIENTRY * qglMultiTexCoord2fARB )( GLenum texture, GLfloat s, GLfloat t );
void ( APIENTRY * qglActiveTextureARB )( GLenum texture );
void ( APIENTRY * qglClientActiveTextureARB )( GLenum texture );
void ( APIENTRY * qglLockArraysEXT )( GLint, GLint );
void ( APIENTRY * qglUnlockArraysEXT )( void );
void ( APIENTRY * qglPNTrianglesiATI )( GLenum pname, GLint param );
void ( APIENTRY * qglPNTrianglesfATI )( GLenum pname, GLfloat param );

// renderer globals / cvars we rely on
extern glconfig_t glConfig;
extern refimport_t ri;

static SDL_Window    *window = NULL;
static SDL_GLContext context = NULL;

// renderer helper (tr_init.c)
qboolean R_GetModeInfo( int *width, int *height, float *windowAspect, int mode );

/*
===============
GLimp_InitExtensions
===============
*/
static void GLimp_InitExtensions( void ) {
	const char *ext = glConfig.extensions_string;

	// multitexture
	qglMultiTexCoord2fARB = NULL;
	qglActiveTextureARB = NULL;
	qglClientActiveTextureARB = NULL;
	if ( r_ext_multitexture->integer && ext && strstr( ext, "GL_ARB_multitexture" ) ) {
		qglMultiTexCoord2fARB = SDL_GL_GetProcAddress( "glMultiTexCoord2fARB" );
		qglActiveTextureARB = SDL_GL_GetProcAddress( "glActiveTextureARB" );
		qglClientActiveTextureARB = SDL_GL_GetProcAddress( "glClientActiveTextureARB" );
		if ( qglActiveTextureARB ) {
			GLint units = 0;
			qglGetIntegerv( GL_MAX_TEXTURE_UNITS_ARB, &units );
			glConfig.maxActiveTextures = units;
			if ( glConfig.maxActiveTextures < 2 ) {
				qglMultiTexCoord2fARB = NULL;
				qglActiveTextureARB = NULL;
				qglClientActiveTextureARB = NULL;
				ri.Printf( PRINT_ALL, "...not using GL_ARB_multitexture, < 2 texture units\n" );
			} else {
				ri.Printf( PRINT_ALL, "...using GL_ARB_multitexture (%i units)\n", glConfig.maxActiveTextures );
			}
		}
	} else {
		ri.Printf( PRINT_ALL, "...ignoring GL_ARB_multitexture\n" );
	}

	// compiled vertex arrays
	qglLockArraysEXT = NULL;
	qglUnlockArraysEXT = NULL;
	if ( ext && strstr( ext, "GL_EXT_compiled_vertex_array" ) ) {
		qglLockArraysEXT = SDL_GL_GetProcAddress( "glLockArraysEXT" );
		qglUnlockArraysEXT = SDL_GL_GetProcAddress( "glUnlockArraysEXT" );
		if ( qglLockArraysEXT && qglUnlockArraysEXT ) {
			ri.Printf( PRINT_ALL, "...using GL_EXT_compiled_vertex_array\n" );
		} else {
			qglLockArraysEXT = NULL;
			qglUnlockArraysEXT = NULL;
		}
	}

	// ATI pn_triangles (truform) - almost never present; renderer null-checks
	qglPNTrianglesiATI = NULL;
	qglPNTrianglesfATI = NULL;
	if ( ext && strstr( ext, "GL_ATI_pn_triangles" ) ) {
		qglPNTrianglesiATI = SDL_GL_GetProcAddress( "glPNTrianglesiATI" );
		qglPNTrianglesfATI = SDL_GL_GetProcAddress( "glPNTrianglesfATI" );
	}

	// texture env add
	glConfig.textureEnvAddAvailable = qfalse;
	if ( ext && ( strstr( ext, "GL_ARB_texture_env_add" ) || strstr( ext, "GL_EXT_texture_env_add" ) ) ) {
		glConfig.textureEnvAddAvailable = qtrue;
	}
}

/*
===============
GLimp_Init
===============
*/
void GLimp_Init( void ) {
	int width, height, colorbits, depthbits, stencilbits;
	float aspect;
	Uint32 flags;
	const char *s;

	ri.Printf( PRINT_ALL, "Initializing OpenGL subsystem (SDL2)\n" );

	if ( SDL_WasInit( SDL_INIT_VIDEO ) == 0 ) {
		if ( SDL_InitSubSystem( SDL_INIT_VIDEO ) < 0 ) {
			ri.Error( ERR_FATAL, "SDL_InitSubSystem(VIDEO) failed: %s\n", SDL_GetError() );
		}
	}

	if ( !R_GetModeInfo( &width, &height, &aspect, r_mode->integer ) ) {
		width = 640;
		height = 480;
		aspect = 4.0f / 3.0f;
	}

	colorbits = r_colorbits->integer;
	if ( colorbits == 0 ) {
		colorbits = 24;
	}
	depthbits = r_depthbits->integer;
	if ( depthbits == 0 ) {
		depthbits = 24;
	}
	stencilbits = r_stencilbits->integer;

	SDL_GL_SetAttribute( SDL_GL_RED_SIZE, colorbits >= 24 ? 8 : 5 );
	SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, colorbits >= 24 ? 8 : 5 );
	SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, colorbits >= 24 ? 8 : 5 );
	SDL_GL_SetAttribute( SDL_GL_DEPTH_SIZE, depthbits );
	SDL_GL_SetAttribute( SDL_GL_STENCIL_SIZE, stencilbits );
	SDL_GL_SetAttribute( SDL_GL_DOUBLEBUFFER, 1 );
	if ( r_stereo->integer ) {
		SDL_GL_SetAttribute( SDL_GL_STEREO, 1 );
	}
	// request a legacy (compatibility) context - RTCW uses fixed-function GL
	SDL_GL_SetAttribute( SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY );

	flags = SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI;
	if ( r_fullscreen->integer ) {
		flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
	}

	window = SDL_CreateWindow( "Return to Castle Wolfenstein",
							   SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
							   width, height, flags );
	if ( !window ) {
		ri.Error( ERR_FATAL, "SDL_CreateWindow failed: %s\n", SDL_GetError() );
	}

	context = SDL_GL_CreateContext( window );
	if ( !context ) {
		ri.Error( ERR_FATAL, "SDL_GL_CreateContext failed: %s\n", SDL_GetError() );
	}

	SDL_GL_MakeCurrent( window, context );
	SDL_GL_SetSwapInterval( r_swapInterval->integer ? 1 : 0 );

	// query the actual drawable size (may differ on HiDPI)
	SDL_GL_GetDrawableSize( window, &width, &height );

	memset( &glConfig, 0, sizeof( glConfig ) );

	s = (const char *)qglGetString( GL_RENDERER );
	Q_strncpyz( glConfig.renderer_string, s ? s : "", sizeof( glConfig.renderer_string ) );
	s = (const char *)qglGetString( GL_VENDOR );
	Q_strncpyz( glConfig.vendor_string, s ? s : "", sizeof( glConfig.vendor_string ) );
	s = (const char *)qglGetString( GL_VERSION );
	Q_strncpyz( glConfig.version_string, s ? s : "", sizeof( glConfig.version_string ) );
	s = (const char *)qglGetString( GL_EXTENSIONS );
	Q_strncpyz( glConfig.extensions_string, s ? s : "", sizeof( glConfig.extensions_string ) );

	qglGetIntegerv( GL_MAX_TEXTURE_SIZE, &glConfig.maxTextureSize );
	if ( glConfig.maxTextureSize <= 0 ) {
		glConfig.maxTextureSize = 256;
	}
	glConfig.maxActiveTextures = 1;

	{
		int r = 0, g = 0, b = 0, d = 0, st = 0;
		SDL_GL_GetAttribute( SDL_GL_RED_SIZE, &r );
		SDL_GL_GetAttribute( SDL_GL_GREEN_SIZE, &g );
		SDL_GL_GetAttribute( SDL_GL_BLUE_SIZE, &b );
		SDL_GL_GetAttribute( SDL_GL_DEPTH_SIZE, &d );
		SDL_GL_GetAttribute( SDL_GL_STENCIL_SIZE, &st );
		glConfig.colorBits = r + g + b;
		glConfig.depthBits = d;
		glConfig.stencilBits = st;
	}

	glConfig.vidWidth = width;
	glConfig.vidHeight = height;
	glConfig.windowAspect = (float)width / (float)height;
	glConfig.displayFrequency = 60;
	glConfig.isFullscreen = r_fullscreen->integer ? qtrue : qfalse;
	glConfig.stereoEnabled = r_stereo->integer ? qtrue : qfalse;
	glConfig.smpActive = qfalse;
	glConfig.deviceSupportsGamma = qfalse;      // modern macOS: no HW gamma ramp
	glConfig.driverType = GLDRV_ICD;
	glConfig.hardwareType = GLHW_GENERIC;
	glConfig.textureCompression = TC_NONE;

	GLimp_InitExtensions();

	ri.Printf( PRINT_ALL, "GL_RENDERER: %s\n", glConfig.renderer_string );

	// make the window visible and grab input focus
	SDL_ShowWindow( window );
}

/*
===============
GLimp_EndFrame
===============
*/
void GLimp_EndFrame( void ) {
	if ( window ) {
		SDL_GL_SwapWindow( window );
	}
}

/*
===============
GLimp_Shutdown
===============
*/
void GLimp_Shutdown( void ) {
	if ( context ) {
		SDL_GL_DeleteContext( context );
		context = NULL;
	}
	if ( window ) {
		SDL_DestroyWindow( window );
		window = NULL;
	}
	memset( &glConfig, 0, sizeof( glConfig ) );
}

/*
===============
GLimp_SetGamma
===============
*/
void GLimp_SetGamma( unsigned char red[256], unsigned char green[256], unsigned char blue[256] ) {
	Uint16 ramp[3][256];
	int i;

	if ( !window || !glConfig.deviceSupportsGamma ) {
		return;
	}
	for ( i = 0; i < 256; i++ ) {
		ramp[0][i] = ( (Uint16)red[i] ) << 8;
		ramp[1][i] = ( (Uint16)green[i] ) << 8;
		ramp[2][i] = ( (Uint16)blue[i] ) << 8;
	}
	SDL_SetWindowGammaRamp( window, ramp[0], ramp[1], ramp[2] );
}

/*
===============
GLimp_LogComment
===============
*/
void GLimp_LogComment( char *comment ) {
	// no-op (GL call logging not implemented for the SDL backend)
}

/*
===============
Render-thread stubs (SMP not supported on the SDL backend)
===============
*/
qboolean GLimp_SpawnRenderThread( void ( *function )( void ) ) {
	return qfalse;
}

void *GLimp_RendererSleep( void ) {
	return NULL;
}

void GLimp_FrontEndSleep( void ) {
}

void GLimp_WakeRenderer( void *data ) {
}

// expose the window so the input layer can share it
SDL_Window *SDLimp_GetWindow( void ) {
	return window;
}

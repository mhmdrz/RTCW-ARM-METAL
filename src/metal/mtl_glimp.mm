/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

mtl_glimp.mm -- Metal windowing / GLimp implementation. Replaces sdl_glimp.c
when USE_METAL is defined. Creates an SDL Metal window, a CAMetalLayer-backed
MTLDevice/queue shared with the GL-on-Metal shim (mtl_gl.mm), drives frame
boundaries, and fills glConfig. Input/audio continue to use SDL (sdl_input.c,
sdl_snd.c); this file also exposes SDLimp_GetWindow() for the input layer.
===========================================================================
*/
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <SDL.h>
#include <string.h>

#include "mtl_local.h"

extern "C" {
#include "../renderer/tr_local.h"

extern glconfig_t glConfig;
extern refimport_t ri;
extern cvar_t *r_mode;
extern cvar_t *r_fullscreen;
extern cvar_t *r_colorbits;
extern cvar_t *r_stereo;
extern cvar_t *r_swapInterval;
qboolean R_GetModeInfo( int *width, int *height, float *windowAspect, int mode );
}

static SDL_Window   *s_window = NULL;
static SDL_MetalView s_metalView = NULL;

static void createDepth( int w, int h ) {
    MTLTextureDescriptor *dd =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8
                                                           width:w height:h mipmapped:NO];
    dd.usage = MTLTextureUsageRenderTarget;
    dd.storageMode = MTLStorageModePrivate;
    mtl_depthTex = [mtl_device newTextureWithDescriptor:dd];
}

void GLimp_Init( void ) {
    int width, height, colorbits, depthbits, stencilbits;
    float aspect;
    Uint32 flags;

    ri.Printf( PRINT_ALL, "Initializing Metal subsystem (SDL2)\n" );

    // Apple Metal Performance HUD (FPS / frame-time / GPU-memory overlay).
    // Enable with "+set r_metalHud 1" at launch (or the MTL_HUD_ENABLED=1 env
    // var). The Metal driver reads MTL_HUD_ENABLED when the device is created,
    // so set it now -- before MTLCreateSystemDefaultDevice below.
    cvar_t *r_metalHud = ri.Cvar_Get( "r_metalHud", "0", CVAR_ARCHIVE | CVAR_LATCH );
    if ( r_metalHud->integer ) {
        setenv( "MTL_HUD_ENABLED", "1", 1 );
    }

    if ( SDL_WasInit( SDL_INIT_VIDEO ) == 0 ) {
        if ( SDL_InitSubSystem( SDL_INIT_VIDEO ) < 0 ) {
            ri.Error( ERR_FATAL, "SDL_InitSubSystem(VIDEO) failed: %s\n", SDL_GetError() );
        }
    }

    if ( !R_GetModeInfo( &width, &height, &aspect, r_mode->integer ) ) {
        width = 640; height = 480; aspect = 4.0f/3.0f;
    }
    colorbits = r_colorbits->integer ? r_colorbits->integer : 24;
    depthbits = 24; stencilbits = 8;

    flags = SDL_WINDOW_METAL | SDL_WINDOW_ALLOW_HIGHDPI;
    if ( r_fullscreen->integer ) flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;

    s_window = SDL_CreateWindow( "Return to Castle Wolfenstein",
                                 SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                 width, height, flags );
    if ( !s_window ) ri.Error( ERR_FATAL, "SDL_CreateWindow(Metal) failed: %s\n", SDL_GetError() );

    s_metalView = SDL_Metal_CreateView( s_window );
    if ( !s_metalView ) ri.Error( ERR_FATAL, "SDL_Metal_CreateView failed: %s\n", SDL_GetError() );

    // __bridge: SDL owns the layer (via the Metal view); no ownership transfer.
    mtl_layer = (__bridge CAMetalLayer *)SDL_Metal_GetLayer( s_metalView );
    mtl_device = MTLCreateSystemDefaultDevice();
    if ( !mtl_device ) ri.Error( ERR_FATAL, "MTLCreateSystemDefaultDevice failed\n" );
    mtl_queue = [mtl_device newCommandQueue];

    mtl_layer.device = mtl_device;
    mtl_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    mtl_layer.framebufferOnly = NO;   // allow readback for screenshots

    // Also enable the HUD via the programmatic API (macOS 13 / iOS 16+), which
    // covers the case where MTL_HUD_ENABLED was not present at device creation.
    if ( r_metalHud->integer || getenv( "MTL_HUD_ENABLED" ) ) {
        if ( @available( macOS 13.0, iOS 16.0, * ) ) {
            mtl_layer.developerHUDProperties = @{ @"mode" : @"default" };
        }
        ri.Printf( PRINT_ALL, "Metal performance HUD enabled\n" );
    }

    int dw = 0, dh = 0;
    SDL_Metal_GetDrawableSize( s_window, &dw, &dh );
    if ( dw <= 0 ) dw = width;
    if ( dh <= 0 ) dh = height;
    mtl_layer.drawableSize = CGSizeMake( dw, dh );
    mtl_drawWidth = dw;
    mtl_drawHeight = dh;

    createDepth( dw, dh );

    MTL_InitBackend();
    MTL_AssignExtensionPointers();

    // ---- glConfig ----
    memset( &glConfig, 0, sizeof( glConfig ) );
    Q_strncpyz( glConfig.renderer_string, "RTCW Metal (GL1.x shim)", sizeof( glConfig.renderer_string ) );
    Q_strncpyz( glConfig.vendor_string, [mtl_device.name UTF8String] ? [mtl_device.name UTF8String] : "Apple",
                sizeof( glConfig.vendor_string ) );
    Q_strncpyz( glConfig.version_string, "OpenGL 1.4 (Metal)", sizeof( glConfig.version_string ) );
    Q_strncpyz( glConfig.extensions_string,
                "GL_ARB_multitexture GL_EXT_texture_env_add GL_EXT_compiled_vertex_array",
                sizeof( glConfig.extensions_string ) );
    glConfig.maxTextureSize = 16384;
    glConfig.maxActiveTextures = 2;
    glConfig.colorBits = colorbits;
    glConfig.depthBits = depthbits;
    glConfig.stencilBits = stencilbits;
    glConfig.vidWidth = dw;
    glConfig.vidHeight = dh;
    glConfig.windowAspect = (float)dw / (float)dh;
    glConfig.displayFrequency = 60;
    glConfig.isFullscreen = r_fullscreen->integer ? qtrue : qfalse;
    glConfig.stereoEnabled = qfalse;
    glConfig.smpActive = qfalse;
    glConfig.deviceSupportsGamma = qfalse;
    glConfig.textureEnvAddAvailable = qtrue;
    glConfig.driverType = GLDRV_ICD;
    glConfig.hardwareType = GLHW_GENERIC;
    glConfig.textureCompression = TC_NONE;

    ri.Printf( PRINT_ALL, "Metal device: %s (%dx%d)\n", glConfig.vendor_string, dw, dh );

    SDL_ShowWindow( s_window );

    // start the first frame so the renderer's first draws have a live encoder
    MTL_BeginFrame();
}

void GLimp_EndFrame( void ) {
    MTL_EndFrame();
    MTL_BeginFrame();
}

void GLimp_Shutdown( void ) {
    MTL_ShutdownBackend();
    mtl_depthTex = nil;
    mtl_queue = nil;
    mtl_device = nil;
    mtl_layer = nil;
    if ( s_metalView ) { SDL_Metal_DestroyView( s_metalView ); s_metalView = NULL; }
    if ( s_window ) { SDL_DestroyWindow( s_window ); s_window = NULL; }
    memset( &glConfig, 0, sizeof( glConfig ) );
}

void GLimp_SetGamma( unsigned char red[256], unsigned char green[256], unsigned char blue[256] ) {
    (void)red; (void)green; (void)blue;   // no HW gamma ramp under Metal
}
void GLimp_LogComment( char *comment ) { (void)comment; }

qboolean GLimp_SpawnRenderThread( void ( *function )( void ) ) { (void)function; return qfalse; }
void *GLimp_RendererSleep( void ) { return NULL; }
void GLimp_FrontEndSleep( void ) {}
void GLimp_WakeRenderer( void *data ) { (void)data; }

// shared with the SDL input layer
extern "C" SDL_Window *SDLimp_GetWindow( void ) { return s_window; }

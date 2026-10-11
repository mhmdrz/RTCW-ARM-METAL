/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

mtl_local.h -- shared state between the Metal GL shim (mtl_gl.mm) and the
Metal GLimp / windowing layer (mtl_glimp.mm). ObjC++ only.
===========================================================================
*/
#ifndef __MTL_LOCAL_H__
#define __MTL_LOCAL_H__

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- shared device / surface (owned by mtl_glimp.mm) ----
extern id<MTLDevice>        mtl_device;
extern id<MTLCommandQueue>  mtl_queue;
extern CAMetalLayer        *mtl_layer;
extern int                  mtl_drawWidth;
extern int                  mtl_drawHeight;

// ---- per-frame objects (managed cooperatively) ----
extern id<MTLCommandBuffer>        mtl_cmd;
extern id<MTLRenderCommandEncoder> mtl_enc;
extern id<CAMetalDrawable>         mtl_drawable;
extern id<MTLTexture>              mtl_depthTex;   // shared depth/stencil

// Called by mtl_glimp at GLimp_Init once the device + layer exist: lets the
// shim build its pipeline library, caches, default textures, etc.
void MTL_InitBackend( void );
void MTL_ShutdownBackend( void );

// Assign the qgl* extension function pointers to the shim's implementations
// (mirrors GLimp_InitExtensions in the GL build).
void MTL_AssignExtensionPointers( void );

// Frame boundaries, driven by GLimp.
//  MTL_BeginFrame: acquire next drawable, make a command buffer + render
//   encoder with a load-clear using the pending clear color.
//  MTL_EndFrame: end encoding, present, commit.
void MTL_BeginFrame( void );
void MTL_EndFrame( void );

// Ensure there is an active render encoder (lazily (re)opens one with a
// load action of "load" so prior contents survive). Returns nil if no
// drawable is available yet.
id<MTLRenderCommandEncoder> MTL_Encoder( void );

// End the current encoder (needed before present or before a clear that must
// use a load-clear pass).
void MTL_EndEncoder( void );

#ifdef __cplusplus
}
#endif

#endif // __MTL_LOCAL_H__

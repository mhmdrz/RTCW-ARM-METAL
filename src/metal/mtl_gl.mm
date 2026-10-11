/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

mtl_gl.mm -- a GL 1.x -> Metal translation shim.

RTCW's renderer drives a bounded subset of fixed-function OpenGL through the
qgl* entry points. This file implements that subset on Apple Metal: a matrix
stack, immediate mode + client arrays, two-unit multitexture with texenv
combine, alpha test, linear/exp fog, blend/depth/cull/stencil state, and
texture management. A single fixed-function emulation shader (below) consumes
uniform-driven texenv/alpha-test/fog so the number of pipeline variants stays
small (keyed only by blend state + color write mask).

Not a general GL driver -- only what RTCW calls is implemented. See the
coverage notes at the end of the port write-up.
===========================================================================
*/
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>
#include <vector>
#include <unordered_map>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "mtl_local.h"
extern "C" {
#include "../renderer/qgl_metal.h"
}

// ============================================================================
// Shared surface objects (defined in mtl_glimp.mm)
// ============================================================================
id<MTLDevice>        mtl_device   = nil;
id<MTLCommandQueue>  mtl_queue    = nil;
CAMetalLayer        *mtl_layer    = nil;
int                  mtl_drawWidth  = 0;
int                  mtl_drawHeight = 0;
id<MTLCommandBuffer>        mtl_cmd      = nil;
id<MTLRenderCommandEncoder> mtl_enc      = nil;
id<CAMetalDrawable>         mtl_drawable = nil;
id<MTLTexture>              mtl_depthTex = nil;

static const MTLPixelFormat MTL_COLOR_FMT = MTLPixelFormatBGRA8Unorm;
static const MTLPixelFormat MTL_DEPTH_FMT = MTLPixelFormatDepth32Float_Stencil8;

// ============================================================================
// Fixed-function emulation shader
// ============================================================================
static const char *s_shaderSrc = R"METAL(
#include <metal_stdlib>
using namespace metal;

struct VIn {
    float4 pos   [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 tc0   [[attribute(2)]];
    float2 tc1   [[attribute(3)]];
};
struct Vertex {
    float4 pos;
    float4 color;
    float2 tc0;
    float2 tc1;
};
struct Uniforms {
    float4x4 mvp;
    float4x4 mv;
    float4   fogColor;
    float    fogStart;
    float    fogEnd;
    float    fogDensity;
    int      fogMode;       // 0 none, 1 linear(0x2601 mapped), 2 exp, 3 exp2
    int      alphaFunc;     // GL compare enum, 0 = disabled
    float    alphaRef;
    int      texEnv0;       // GL_MODULATE/REPLACE/DECAL/ADD, 0 none
    int      texEnv1;
    int      numTex;
};
struct VOut {
    float4 pos [[position]];
    float4 color;
    float2 tc0;
    float2 tc1;
    float  fogc;
};

vertex VOut mtl_vs(uint vid [[vertex_id]],
                   const device Vertex *verts [[buffer(0)]],
                   constant Uniforms &u [[buffer(1)]]) {
    VOut o;
    float4 p = verts[vid].pos;
    o.pos   = u.mvp * p;
    // RTCW builds GL-style projections (clip z in [-w, w]); Metal expects
    // clip z in [0, w]. Remap: z' = (z + w) / 2.
    o.pos.z = (o.pos.z + o.pos.w) * 0.5;
    o.color = verts[vid].color;
    o.tc0   = verts[vid].tc0;
    o.tc1   = verts[vid].tc1;
    float4 eye = u.mv * p;
    o.fogc = length(eye.xyz);
    return o;
}

static float4 combine(float4 c, float4 t, int mode) {
    // 0x2100 MODULATE, 0x1E01 REPLACE, 0x2101 DECAL, 0x0104 ADD
    if (mode == 0x1E01) { return t; }
    if (mode == 0x2101) { return float4(mix(c.rgb, t.rgb, t.a), c.a); }
    if (mode == 0x0104) { return float4(c.rgb + t.rgb, c.a * t.a); }
    return c * t; // MODULATE (default)
}

fragment float4 mtl_fs(VOut in [[stage_in]],
                       constant Uniforms &u [[buffer(1)]],
                       texture2d<float> tex0 [[texture(0)]],
                       sampler s0 [[sampler(0)]],
                       texture2d<float> tex1 [[texture(1)]],
                       sampler s1 [[sampler(1)]]) {
    float4 col = in.color;
    if (u.numTex >= 1) { col = combine(col, tex0.sample(s0, in.tc0), u.texEnv0); }
    if (u.numTex >= 2) { col = combine(col, tex1.sample(s1, in.tc1), u.texEnv1); }

    // fog
    if (u.fogMode != 0) {
        float d = in.fogc;
        float f = 1.0;
        if (u.fogMode == 1) { f = (u.fogEnd - d) / (u.fogEnd - u.fogStart); }
        else if (u.fogMode == 2) { f = exp(-u.fogDensity * d); }
        else { float x = u.fogDensity * d; f = exp(-(x*x)); }
        f = clamp(f, 0.0, 1.0);
        col.rgb = mix(u.fogColor.rgb, col.rgb, f);
    }

    // alpha test (GL compare enums)
    int af = u.alphaFunc;
    if (af != 0) {
        float a = col.a, r = u.alphaRef;
        bool pass = true;
        if      (af == 0x0200) pass = false;              // NEVER
        else if (af == 0x0201) pass = (a <  r);           // LESS
        else if (af == 0x0202) pass = (a == r);           // EQUAL
        else if (af == 0x0203) pass = (a <= r);           // LEQUAL
        else if (af == 0x0204) pass = (a >  r);           // GREATER
        else if (af == 0x0205) pass = (a != r);           // NOTEQUAL
        else if (af == 0x0206) pass = (a >= r);           // GEQUAL
        else                   pass = true;               // ALWAYS/other
        if (!pass) discard_fragment();
    }
    return col;
}
)METAL";

// ============================================================================
// CPU-side types
// ============================================================================
typedef struct {
    simd_float4 pos;
    simd_float4 color;
    simd_float2 tc0;
    simd_float2 tc1;
} MtlVertex;

typedef struct {
    simd_float4x4 mvp;
    simd_float4x4 mv;
    simd_float4   fogColor;
    float         fogStart, fogEnd, fogDensity;
    int           fogMode;
    int           alphaFunc;
    float         alphaRef;
    int           texEnv0, texEnv1, numTex;
    int           _pad;
} MtlUniforms;

typedef struct {
    GLboolean enabled;
    GLint     size;
    GLenum    type;
    GLsizei   stride;
    const void *ptr;
} ClientArray;

typedef struct {
    id<MTLTexture>      tex;
    GLenum              minFilter, magFilter, wrapS, wrapT;
    id<MTLSamplerState> sampler;
    bool                dirty;   // sampler needs rebuild
} MtlTexObj;

// ============================================================================
// GL state
// ============================================================================
#define MAX_MATRIX_STACK 64

static std::vector<simd_float4x4> s_mvStack(1, matrix_identity_float4x4);
static std::vector<simd_float4x4> s_projStack(1, matrix_identity_float4x4);
static GLenum s_matrixMode = GL_MODELVIEW;

static simd_float4 s_curColor = {1,1,1,1};
static simd_float2 s_curTC[2] = {{0,0},{0,0}};

static GLenum s_beginMode = 0;
static std::vector<MtlVertex> s_imVerts;

static ClientArray s_vtxArray = {0,0,0,0,0};
static ClientArray s_colArray = {0,0,0,0,0};
static ClientArray s_tcArray[2] = {{0,0,0,0,0},{0,0,0,0,0}};
static ClientArray s_nrmArray = {0,0,0,0,0};

static int s_serverTexUnit = 0;   // qglActiveTextureARB
static int s_clientTexUnit = 0;   // qglClientActiveTextureARB

static GLuint s_boundTex[2] = {0,0};
static GLboolean s_texEnabled[2] = {0,0};
static GLenum s_texEnvMode[2] = {GL_MODULATE, GL_MODULATE};

// raster / fragment state
static GLboolean s_blend = 0;
static GLenum s_blendSrc = GL_ONE, s_blendDst = GL_ZERO;
static GLboolean s_depthTest = 0;
static GLenum s_depthFunc = GL_LEQUAL;
static GLboolean s_depthMask = 1;
static GLboolean s_cull = 0;
static GLenum s_cullFace = GL_FRONT;
static GLboolean s_colorMask[4] = {1,1,1,1};
static GLboolean s_alphaTest = 0;
static GLenum s_alphaFunc = GL_ALWAYS;
static float s_alphaRef = 0;
static GLboolean s_fog = 0;
static GLenum s_fogMode = GL_EXP;
static simd_float4 s_fogColor = {0,0,0,1};
static float s_fogStart = 0, s_fogEnd = 1, s_fogDensity = 1;
static GLboolean s_scissor = 0;
static int s_scissorBox[4] = {0,0,0,0};
static GLboolean s_polyOffset = 0;
static float s_polyOffsetFactor = 0, s_polyOffsetUnits = 0;
static int s_viewport[4] = {0,0,0,0};
static double s_depthRange[2] = {0,1};
static GLenum s_polygonMode = GL_FILL;

// stencil
static GLboolean s_stencil = 0;
static GLenum s_stencilFunc = GL_ALWAYS;
static GLint s_stencilRef = 0;
static GLuint s_stencilValMask = 0xFF, s_stencilWriteMask = 0xFF;
static GLenum s_stencilFail = GL_KEEP, s_stencilZFail = GL_KEEP, s_stencilZPass = GL_KEEP;

// clear values + pending frame load actions
static simd_float4 s_clearColor = {0,0,0,1};
static double s_clearDepth = 1.0;
static int s_clearStencil = 0;
static MTLLoadAction s_pendColorLoad = MTLLoadActionLoad;
static MTLLoadAction s_pendDepthLoad = MTLLoadActionLoad;
static MTLLoadAction s_pendStencilLoad = MTLLoadActionLoad;

// textures
static std::unordered_map<GLuint, MtlTexObj> s_textures;
static GLuint s_nextTexName = 1;

// ============================================================================
// Metal objects / caches
// ============================================================================
static id<MTLLibrary>  s_lib = nil;
static id<MTLFunction> s_vs = nil, s_fs = nil;

struct PipeKey {
    uint32_t v;
    bool operator==(const PipeKey&o) const { return v==o.v; }
};
struct PipeKeyHash { size_t operator()(const PipeKey&k) const { return k.v; } };
static std::unordered_map<uint32_t, id<MTLRenderPipelineState>> s_pipeCache;

struct DSKey { uint64_t v; };
static std::unordered_map<uint64_t, id<MTLDepthStencilState>> s_dsCache;

// ============================================================================
// Helpers
// ============================================================================
static MTLBlendFactor glToBlend( GLenum f ) {
    switch (f) {
        case GL_ZERO: return MTLBlendFactorZero;
        case GL_ONE: return MTLBlendFactorOne;
        case GL_SRC_COLOR: return MTLBlendFactorSourceColor;
        case GL_ONE_MINUS_SRC_COLOR: return MTLBlendFactorOneMinusSourceColor;
        case GL_DST_COLOR: return MTLBlendFactorDestinationColor;
        case GL_ONE_MINUS_DST_COLOR: return MTLBlendFactorOneMinusDestinationColor;
        case GL_SRC_ALPHA: return MTLBlendFactorSourceAlpha;
        case GL_ONE_MINUS_SRC_ALPHA: return MTLBlendFactorOneMinusSourceAlpha;
        case GL_DST_ALPHA: return MTLBlendFactorDestinationAlpha;
        case GL_ONE_MINUS_DST_ALPHA: return MTLBlendFactorOneMinusDestinationAlpha;
        case GL_SRC_ALPHA_SATURATE: return MTLBlendFactorSourceAlphaSaturated;
        default: return MTLBlendFactorOne;
    }
}
static MTLCompareFunction glToCompare( GLenum f ) {
    switch (f) {
        case GL_NEVER: return MTLCompareFunctionNever;
        case GL_LESS: return MTLCompareFunctionLess;
        case GL_EQUAL: return MTLCompareFunctionEqual;
        case GL_LEQUAL: return MTLCompareFunctionLessEqual;
        case GL_GREATER: return MTLCompareFunctionGreater;
        case GL_NOTEQUAL: return MTLCompareFunctionNotEqual;
        case GL_GEQUAL: return MTLCompareFunctionGreaterEqual;
        case GL_ALWAYS: return MTLCompareFunctionAlways;
        default: return MTLCompareFunctionAlways;
    }
}
static MTLStencilOperation glToStencilOp( GLenum o ) {
    switch (o) {
        case GL_KEEP: return MTLStencilOperationKeep;
        case GL_ZERO: return MTLStencilOperationZero;
        case GL_REPLACE: return MTLStencilOperationReplace;
        case GL_INCR: return MTLStencilOperationIncrementClamp;
        case GL_DECR: return MTLStencilOperationDecrementClamp;
        case GL_INVERT: return MTLStencilOperationInvert;
        case 0x8507: return MTLStencilOperationIncrementWrap;  // GL_INCR_WRAP
        case 0x8508: return MTLStencilOperationDecrementWrap;  // GL_DECR_WRAP
        default: return MTLStencilOperationKeep;
    }
}

static simd_float4x4 matFromGL( const GLfloat *m ) {
    simd_float4x4 r;
    for (int c=0;c<4;c++)
        r.columns[c] = (simd_float4){ m[c*4+0], m[c*4+1], m[c*4+2], m[c*4+3] };
    return r;
}
static std::vector<simd_float4x4> &curStack() {
    return (s_matrixMode == GL_PROJECTION) ? s_projStack : s_mvStack;
}

// ---- pipeline / depth-stencil state objects ----
static id<MTLRenderPipelineState> getPipeline( void ) {
    // key: blend(1) | src(5b) | dst(5b) | colorMask(4b)
    uint32_t key = (s_blend?1u:0u);
    key |= ((uint32_t)(s_blendSrc & 0x1F)) << 1;
    key |= ((uint32_t)(s_blendDst & 0x1F)) << 6;
    uint32_t cm = (s_colorMask[0]?1:0)|(s_colorMask[1]?2:0)|(s_colorMask[2]?4:0)|(s_colorMask[3]?8:0);
    key |= cm << 11;
    auto it = s_pipeCache.find(key);
    if (it != s_pipeCache.end()) return it->second;

    MTLVertexDescriptor *vd = [[MTLVertexDescriptor alloc] init];
    // single interleaved buffer(0); matches `Vertex` struct in the shader
    vd.attributes[0].format = MTLVertexFormatFloat4; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = 0;
    vd.attributes[1].format = MTLVertexFormatFloat4; vd.attributes[1].offset = 16; vd.attributes[1].bufferIndex = 0;
    vd.attributes[2].format = MTLVertexFormatFloat2; vd.attributes[2].offset = 32; vd.attributes[2].bufferIndex = 0;
    vd.attributes[3].format = MTLVertexFormatFloat2; vd.attributes[3].offset = 40; vd.attributes[3].bufferIndex = 0;
    vd.layouts[0].stride = sizeof(MtlVertex);
    vd.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction = s_vs;
    pd.fragmentFunction = s_fs;
    pd.vertexDescriptor = vd;
    pd.colorAttachments[0].pixelFormat = MTL_COLOR_FMT;
    pd.depthAttachmentPixelFormat = MTL_DEPTH_FMT;
    pd.stencilAttachmentPixelFormat = MTL_DEPTH_FMT;
    MTLColorWriteMask wm = MTLColorWriteMaskNone;
    if (s_colorMask[0]) wm |= MTLColorWriteMaskRed;
    if (s_colorMask[1]) wm |= MTLColorWriteMaskGreen;
    if (s_colorMask[2]) wm |= MTLColorWriteMaskBlue;
    if (s_colorMask[3]) wm |= MTLColorWriteMaskAlpha;
    pd.colorAttachments[0].writeMask = wm;
    pd.colorAttachments[0].blendingEnabled = s_blend ? YES : NO;
    if (s_blend) {
        pd.colorAttachments[0].sourceRGBBlendFactor = glToBlend(s_blendSrc);
        pd.colorAttachments[0].destinationRGBBlendFactor = glToBlend(s_blendDst);
        pd.colorAttachments[0].sourceAlphaBlendFactor = glToBlend(s_blendSrc);
        pd.colorAttachments[0].destinationAlphaBlendFactor = glToBlend(s_blendDst);
        pd.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pd.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    }
    NSError *err = nil;
    id<MTLRenderPipelineState> ps = [mtl_device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!ps) { NSLog(@"mtl_gl: pipeline failed: %@", err); return nil; }
    s_pipeCache[key] = ps;
    return ps;
}

static id<MTLDepthStencilState> getDepthStencil( void ) {
    uint64_t key = 0;
    key |= (s_depthTest?1ull:0ull);
    key |= ((uint64_t)(s_depthFunc & 0xFFFF)) << 1;
    key |= (s_depthMask?1ull:0ull) << 17;
    key |= (s_stencil?1ull:0ull) << 18;
    key |= ((uint64_t)(s_stencilFunc & 0xFFFF)) << 19;
    key |= ((uint64_t)(s_stencilFail & 0x7)) << 35;
    key |= ((uint64_t)(s_stencilZFail & 0x7)) << 38;
    key |= ((uint64_t)(s_stencilZPass & 0x7)) << 41;
    auto it = s_dsCache.find(key);
    if (it != s_dsCache.end()) return it->second;

    MTLDepthStencilDescriptor *dd = [[MTLDepthStencilDescriptor alloc] init];
    dd.depthCompareFunction = s_depthTest ? glToCompare(s_depthFunc) : MTLCompareFunctionAlways;
    dd.depthWriteEnabled = (s_depthMask && s_depthTest) ? YES : (s_depthMask ? YES : NO);
    if (s_stencil) {
        MTLStencilDescriptor *sd = [[MTLStencilDescriptor alloc] init];
        sd.stencilCompareFunction = glToCompare(s_stencilFunc);
        sd.stencilFailureOperation = glToStencilOp(s_stencilFail);
        sd.depthFailureOperation = glToStencilOp(s_stencilZFail);
        sd.depthStencilPassOperation = glToStencilOp(s_stencilZPass);
        sd.readMask = s_stencilValMask;
        sd.writeMask = s_stencilWriteMask;
        dd.frontFaceStencil = sd;
        dd.backFaceStencil = sd;
    }
    id<MTLDepthStencilState> ds = [mtl_device newDepthStencilStateWithDescriptor:dd];
    s_dsCache[key] = ds;
    return ds;
}

static id<MTLSamplerState> buildSampler( MtlTexObj &t ) {
    MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
    sd.minFilter = (t.minFilter==GL_NEAREST||t.minFilter==GL_NEAREST_MIPMAP_NEAREST||t.minFilter==GL_NEAREST_MIPMAP_LINEAR)
                   ? MTLSamplerMinMagFilterNearest : MTLSamplerMinMagFilterLinear;
    sd.magFilter = (t.magFilter==GL_NEAREST) ? MTLSamplerMinMagFilterNearest : MTLSamplerMinMagFilterLinear;
    bool mip = (t.minFilter==GL_NEAREST_MIPMAP_NEAREST||t.minFilter==GL_LINEAR_MIPMAP_NEAREST||
                t.minFilter==GL_NEAREST_MIPMAP_LINEAR||t.minFilter==GL_LINEAR_MIPMAP_LINEAR);
    sd.mipFilter = mip ? ((t.minFilter==GL_NEAREST_MIPMAP_NEAREST||t.minFilter==GL_LINEAR_MIPMAP_NEAREST)
                          ? MTLSamplerMipFilterNearest : MTLSamplerMipFilterLinear)
                       : MTLSamplerMipFilterNotMipmapped;
    sd.sAddressMode = (t.wrapS==GL_REPEAT) ? MTLSamplerAddressModeRepeat : MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = (t.wrapT==GL_REPEAT) ? MTLSamplerAddressModeRepeat : MTLSamplerAddressModeClampToEdge;
    sd.maxAnisotropy = 1;
    return [mtl_device newSamplerStateWithDescriptor:sd];
}

// ============================================================================
// Frame / encoder management
// ============================================================================
void MTL_EndEncoder( void ) {
    if (mtl_enc) { [mtl_enc endEncoding]; mtl_enc = nil; }
}

id<MTLRenderCommandEncoder> MTL_Encoder( void ) {
    if (mtl_enc) return mtl_enc;
    if (!mtl_drawable || !mtl_cmd) return nil;
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = mtl_drawable.texture;
    rp.colorAttachments[0].loadAction = s_pendColorLoad;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(s_clearColor.x, s_clearColor.y, s_clearColor.z, s_clearColor.w);
    rp.depthAttachment.texture = mtl_depthTex;
    rp.depthAttachment.loadAction = s_pendDepthLoad;
    rp.depthAttachment.storeAction = MTLStoreActionStore;
    rp.depthAttachment.clearDepth = s_clearDepth;
    rp.stencilAttachment.texture = mtl_depthTex;
    rp.stencilAttachment.loadAction = s_pendStencilLoad;
    rp.stencilAttachment.storeAction = MTLStoreActionStore;
    rp.stencilAttachment.clearStencil = s_clearStencil;
    mtl_enc = [mtl_cmd renderCommandEncoderWithDescriptor:rp];
    // consumed: subsequent (re)opens preserve contents unless another clear is requested
    s_pendColorLoad = MTLLoadActionLoad;
    s_pendDepthLoad = MTLLoadActionLoad;
    s_pendStencilLoad = MTLLoadActionLoad;
    return mtl_enc;
}

void MTL_BeginFrame( void ) {
    mtl_drawable = [mtl_layer nextDrawable];
    mtl_cmd = [mtl_queue commandBuffer];
    // start the frame with a clear (RTCW issues its own glClear too, but this
    // guarantees a defined surface)
    s_pendColorLoad = MTLLoadActionClear;
    s_pendDepthLoad = MTLLoadActionClear;
    s_pendStencilLoad = MTLLoadActionClear;
}

void MTL_EndFrame( void ) {
    // flush any pending clears even if nothing drew this frame
    if (!mtl_enc && (s_pendColorLoad==MTLLoadActionClear)) MTL_Encoder();
    MTL_EndEncoder();
    if (mtl_drawable) [mtl_cmd presentDrawable:mtl_drawable];
    [mtl_cmd commit];
    mtl_cmd = nil;
    mtl_drawable = nil;
}

// ============================================================================
// Draw submission
// ============================================================================
static MtlVertex fetchVertex( int idx ) {
    MtlVertex v;
    v.pos = (simd_float4){0,0,0,1};
    v.color = s_curColor;
    v.tc0 = s_curTC[0];
    v.tc1 = s_curTC[1];
    if (s_vtxArray.enabled && s_vtxArray.ptr) {
        const char *p = (const char*)s_vtxArray.ptr + (size_t)idx * (s_vtxArray.stride ? s_vtxArray.stride : (s_vtxArray.size*sizeof(float)));
        const float *f = (const float*)p;
        v.pos.x = f[0]; v.pos.y = f[1];
        v.pos.z = (s_vtxArray.size >= 3) ? f[2] : 0.0f;
        v.pos.w = (s_vtxArray.size >= 4) ? f[3] : 1.0f;
    }
    if (s_colArray.enabled && s_colArray.ptr) {
        size_t st = s_colArray.stride ? s_colArray.stride
                    : (size_t)s_colArray.size * (s_colArray.type==GL_FLOAT?sizeof(float):1);
        const char *p = (const char*)s_colArray.ptr + (size_t)idx*st;
        if (s_colArray.type == GL_FLOAT) {
            const float *f=(const float*)p;
            v.color = (simd_float4){ f[0],f[1],f[2], s_colArray.size>=4?f[3]:1.0f };
        } else { // GL_UNSIGNED_BYTE
            const unsigned char *b=(const unsigned char*)p;
            v.color = (simd_float4){ b[0]/255.0f,b[1]/255.0f,b[2]/255.0f, s_colArray.size>=4?b[3]/255.0f:1.0f };
        }
    }
    for (int u=0; u<2; u++) {
        if (s_tcArray[u].enabled && s_tcArray[u].ptr) {
            size_t st = s_tcArray[u].stride ? s_tcArray[u].stride : (size_t)s_tcArray[u].size*sizeof(float);
            const float *f = (const float*)((const char*)s_tcArray[u].ptr + (size_t)idx*st);
            simd_float2 t = { f[0], f[1] };
            if (u==0) v.tc0 = t; else v.tc1 = t;
        }
    }
    return v;
}

// convert a vertex list under a GL primitive mode into a triangle/line list
static void emitPrimitives( std::vector<MtlVertex> &out, const std::vector<MtlVertex> &in,
                            GLenum mode, MTLPrimitiveType &primOut, bool &isLine ) {
    isLine = false;
    size_t n = in.size();
    switch (mode) {
        case GL_POINTS:
            primOut = MTLPrimitiveTypePoint; out = in; break;
        case GL_TRIANGLES:
            primOut = MTLPrimitiveTypeTriangle; out = in; break;
        case GL_TRIANGLE_STRIP:
            primOut = MTLPrimitiveTypeTriangle;
            for (size_t i=2;i<n;i++) {
                if (i & 1) { out.push_back(in[i-1]); out.push_back(in[i-2]); out.push_back(in[i]); }
                else       { out.push_back(in[i-2]); out.push_back(in[i-1]); out.push_back(in[i]); }
            }
            break;
        case GL_TRIANGLE_FAN:
        case GL_POLYGON:
            primOut = MTLPrimitiveTypeTriangle;
            for (size_t i=2;i<n;i++) { out.push_back(in[0]); out.push_back(in[i-1]); out.push_back(in[i]); }
            break;
        case GL_QUADS:
            primOut = MTLPrimitiveTypeTriangle;
            for (size_t i=0;i+3<n;i+=4) {
                out.push_back(in[i]); out.push_back(in[i+1]); out.push_back(in[i+2]);
                out.push_back(in[i]); out.push_back(in[i+2]); out.push_back(in[i+3]);
            }
            break;
        case GL_LINES:
            primOut = MTLPrimitiveTypeLine; isLine = true; out = in; break;
        case GL_LINE_LOOP:
        case GL_LINE_STRIP:
            primOut = MTLPrimitiveTypeLineStrip; isLine = true; out = in;
            if (mode==GL_LINE_LOOP && n>1) out.push_back(in[0]);
            break;
        default:
            primOut = MTLPrimitiveTypeTriangle; out = in; break;
    }
}

static void drawVertexList( std::vector<MtlVertex> &verts, GLenum mode ) {
    if (verts.empty() || !mtl_device) return;
    id<MTLRenderCommandEncoder> enc = MTL_Encoder();
    if (!enc) return;

    std::vector<MtlVertex> tri;
    tri.reserve(verts.size());
    MTLPrimitiveType prim; bool isLine;
    emitPrimitives(tri, verts, mode, prim, isLine);
    if (tri.empty()) return;

    // pipeline + depth-stencil + raster state
    id<MTLRenderPipelineState> ps = getPipeline();
    if (!ps) return;
    [enc setRenderPipelineState:ps];
    [enc setDepthStencilState:getDepthStencil()];
    if (s_stencil) [enc setStencilReferenceValue:(uint32_t)s_stencilRef];
    [enc setCullMode: s_cull ? (s_cullFace==GL_FRONT?MTLCullModeFront:MTLCullModeBack) : MTLCullModeNone];
    [enc setFrontFacingWinding:MTLWindingCounterClockwise];
    if (s_polyOffset) [enc setDepthBias:s_polyOffsetUnits slopeScale:s_polyOffsetFactor clamp:0];
    else              [enc setDepthBias:0 slopeScale:0 clamp:0];

    // viewport (respect depth range)
    MTLViewport vp;
    vp.originX = s_viewport[0]; vp.originY = s_viewport[1];
    vp.width = s_viewport[2]; vp.height = s_viewport[3];
    vp.znear = s_depthRange[0]; vp.zfar = s_depthRange[1];
    if (vp.width <= 0) { vp.width = mtl_drawWidth; }
    if (vp.height <= 0) { vp.height = mtl_drawHeight; }
    // GL origin is bottom-left, Metal top-left: flip Y
    vp.originY = mtl_drawHeight - (s_viewport[1] + s_viewport[3]);
    [enc setViewport:vp];

    if (s_scissor) {
        MTLScissorRect sr;
        int x = s_scissorBox[0];
        int y = mtl_drawHeight - (s_scissorBox[1] + s_scissorBox[3]);
        int w = s_scissorBox[2], h = s_scissorBox[3];
        if (x<0){w+=x;x=0;} if (y<0){h+=y;y=0;}
        if (x+w > mtl_drawWidth)  w = mtl_drawWidth  - x;
        if (y+h > mtl_drawHeight) h = mtl_drawHeight - y;
        if (w<0) w=0; if (h<0) h=0;
        sr.x=x; sr.y=y; sr.width=w; sr.height=h;
        [enc setScissorRect:sr];
    } else {
        MTLScissorRect sr = {0,0,(NSUInteger)mtl_drawWidth,(NSUInteger)mtl_drawHeight};
        [enc setScissorRect:sr];
    }

    // uniforms
    MtlUniforms u;
    u.mvp = matrix_multiply(s_projStack.back(), s_mvStack.back());
    u.mv  = s_mvStack.back();
    u.fogColor = s_fogColor;
    u.fogStart = s_fogStart; u.fogEnd = s_fogEnd; u.fogDensity = s_fogDensity;
    u.fogMode = 0;
    if (s_fog) u.fogMode = (s_fogMode==GL_LINEAR)?1:((s_fogMode==GL_EXP2)?3:2);
    u.alphaFunc = s_alphaTest ? (int)s_alphaFunc : 0;
    u.alphaRef = s_alphaRef;
    int nt = 0;
    if (s_texEnabled[0] && s_boundTex[0]) nt = 1;
    if (nt==1 && s_texEnabled[1] && s_boundTex[1]) nt = 2;
    u.numTex = nt;
    u.texEnv0 = (int)s_texEnvMode[0];
    u.texEnv1 = (int)s_texEnvMode[1];

    // bind textures / samplers
    for (int unit=0; unit<2; unit++) {
        GLuint tn = s_boundTex[unit];
        if (tn && s_textures.count(tn)) {
            MtlTexObj &t = s_textures[tn];
            if (!t.sampler || t.dirty) { t.sampler = buildSampler(t); t.dirty = false; }
            [enc setFragmentTexture:t.tex atIndex:unit];
            [enc setFragmentSamplerState:t.sampler atIndex:unit];
        }
    }

    id<MTLBuffer> vb = [mtl_device newBufferWithBytes:tri.data()
                                               length:tri.size()*sizeof(MtlVertex)
                                              options:MTLResourceStorageModeShared];
    [enc setVertexBuffer:vb offset:0 atIndex:0];
    [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
    [enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
    [enc drawPrimitives:prim vertexStart:0 vertexCount:tri.size()];
}

// ============================================================================
// Backend init / shutdown (called from mtl_glimp)
// ============================================================================
void MTL_InitBackend( void ) {
    NSError *err = nil;
    NSString *src = [NSString stringWithUTF8String:s_shaderSrc];
    MTLCompileOptions *opt = [[MTLCompileOptions alloc] init];
    s_lib = [mtl_device newLibraryWithSource:src options:opt error:&err];
    if (!s_lib) { NSLog(@"mtl_gl: shader compile failed: %@", err); return; }
    s_vs = [s_lib newFunctionWithName:@"mtl_vs"];
    s_fs = [s_lib newFunctionWithName:@"mtl_fs"];
    s_viewport[2] = mtl_drawWidth;
    s_viewport[3] = mtl_drawHeight;
}

void MTL_ShutdownBackend( void ) {
    s_pipeCache.clear();
    s_dsCache.clear();
    s_textures.clear();
}

// ============================================================================
//  qgl* entry points
// ============================================================================
extern "C" {

// ---- matrix stack ----
void qglMatrixMode( GLenum m ) { s_matrixMode = m; }
void qglLoadIdentity( void ) { curStack().back() = matrix_identity_float4x4; }
void qglLoadMatrixf( const GLfloat *m ) { curStack().back() = matFromGL(m); }
void qglPushMatrix( void ) { std::vector<simd_float4x4> &s=curStack(); if (s.size()<MAX_MATRIX_STACK) s.push_back(s.back()); }
void qglPopMatrix( void ) { std::vector<simd_float4x4> &s=curStack(); if (s.size()>1) s.pop_back(); }
void qglTranslatef( GLfloat x, GLfloat y, GLfloat z ) {
    simd_float4x4 t = matrix_identity_float4x4;
    t.columns[3] = (simd_float4){x,y,z,1};
    curStack().back() = matrix_multiply(curStack().back(), t);
}
void qglOrtho( GLdouble l, GLdouble r, GLdouble b, GLdouble t, GLdouble n, GLdouble f ) {
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = 2.0/(r-l);
    m.columns[1].y = 2.0/(t-b);
    m.columns[2].z = -2.0/(f-n);
    m.columns[3] = (simd_float4){ (float)(-(r+l)/(r-l)), (float)(-(t+b)/(t-b)), (float)(-(f+n)/(f-n)), 1 };
    curStack().back() = matrix_multiply(curStack().back(), m);
}

// ---- immediate mode ----
void qglBegin( GLenum mode ) { s_beginMode = mode; s_imVerts.clear(); }
void qglEnd( void ) { if (!s_imVerts.empty()) drawVertexList(s_imVerts, s_beginMode); s_imVerts.clear(); s_beginMode = 0; }
static void imPush( float x, float y, float z ) {
    MtlVertex v; v.pos=(simd_float4){x,y,z,1}; v.color=s_curColor; v.tc0=s_curTC[0]; v.tc1=s_curTC[1];
    s_imVerts.push_back(v);
}
void qglVertex2f( GLfloat x, GLfloat y ) { imPush(x,y,0); }
void qglVertex3f( GLfloat x, GLfloat y, GLfloat z ) { imPush(x,y,z); }
void qglVertex3fv( const GLfloat *v ) { imPush(v[0],v[1],v[2]); }
void qglColor3f( GLfloat r, GLfloat g, GLfloat b ) { s_curColor=(simd_float4){r,g,b,1}; }
void qglColor4f( GLfloat r, GLfloat g, GLfloat b, GLfloat a ) { s_curColor=(simd_float4){r,g,b,a}; }
void qglColor3fv( const GLfloat *v ) { s_curColor=(simd_float4){v[0],v[1],v[2],1}; }
void qglColor4ubv( const GLubyte *v ) { s_curColor=(simd_float4){v[0]/255.0f,v[1]/255.0f,v[2]/255.0f,v[3]/255.0f}; }
void qglTexCoord2f( GLfloat s, GLfloat t ) { s_curTC[0]=(simd_float2){s,t}; }
void qglTexCoord2fv( const GLfloat *v ) { s_curTC[0]=(simd_float2){v[0],v[1]}; }

// ---- client arrays ----
void qglEnableClientState( GLenum a ) {
    switch(a){
        case GL_VERTEX_ARRAY: s_vtxArray.enabled=1; break;
        case GL_COLOR_ARRAY: s_colArray.enabled=1; break;
        case GL_NORMAL_ARRAY: s_nrmArray.enabled=1; break;
        case GL_TEXTURE_COORD_ARRAY: s_tcArray[s_clientTexUnit].enabled=1; break;
    }
}
void qglDisableClientState( GLenum a ) {
    switch(a){
        case GL_VERTEX_ARRAY: s_vtxArray.enabled=0; break;
        case GL_COLOR_ARRAY: s_colArray.enabled=0; break;
        case GL_NORMAL_ARRAY: s_nrmArray.enabled=0; break;
        case GL_TEXTURE_COORD_ARRAY: s_tcArray[s_clientTexUnit].enabled=0; break;
    }
}
void qglVertexPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *p ) {
    s_vtxArray.size=size; s_vtxArray.type=type; s_vtxArray.stride=stride; s_vtxArray.ptr=p;
}
void qglColorPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *p ) {
    s_colArray.size=size; s_colArray.type=type; s_colArray.stride=stride; s_colArray.ptr=p;
}
void qglTexCoordPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *p ) {
    ClientArray &a = s_tcArray[s_clientTexUnit];
    a.size=size; a.type=type; a.stride=stride; a.ptr=p;
}
void qglNormalPointer( GLenum type, GLsizei stride, const GLvoid *p ) {
    s_nrmArray.type=type; s_nrmArray.stride=stride; s_nrmArray.ptr=p; s_nrmArray.size=3;
}
void qglArrayElement( GLint i ) { s_imVerts.push_back(fetchVertex(i)); }
void qglDrawElements( GLenum mode, GLsizei count, GLenum type, const GLvoid *indices ) {
    std::vector<MtlVertex> verts; verts.reserve(count);
    if (type == GL_UNSIGNED_INT) {
        const unsigned int *idx=(const unsigned int*)indices;
        for (int i=0;i<count;i++) verts.push_back(fetchVertex(idx[i]));
    } else if (type == GL_UNSIGNED_SHORT) {
        const unsigned short *idx=(const unsigned short*)indices;
        for (int i=0;i<count;i++) verts.push_back(fetchVertex(idx[i]));
    } else {
        const unsigned char *idx=(const unsigned char*)indices;
        for (int i=0;i<count;i++) verts.push_back(fetchVertex(idx[i]));
    }
    drawVertexList(verts, mode);
}

// ---- multitexture / extension impls (assigned to the qgl* pointers) ----
static void MTLAPI_MultiTexCoord2fARB( GLenum tex, GLfloat s, GLfloat t ) {
    int u = (int)(tex - GL_TEXTURE0_ARB); if (u<0||u>1) u=0;
    s_curTC[u] = (simd_float2){s,t};
}
static void MTLAPI_ActiveTextureARB( GLenum tex ) { int u=(int)(tex-GL_TEXTURE0_ARB); s_serverTexUnit=(u>=0&&u<2)?u:0; }
static void MTLAPI_ClientActiveTextureARB( GLenum tex ) { int u=(int)(tex-GL_TEXTURE0_ARB); s_clientTexUnit=(u>=0&&u<2)?u:0; }
static void MTLAPI_LockArraysEXT( GLint a, GLint b ) { (void)a;(void)b; }
static void MTLAPI_UnlockArraysEXT( void ) {}
static void MTLAPI_PNTrianglesiATI( GLenum p, GLint v ) { (void)p;(void)v; }
static void MTLAPI_PNTrianglesfATI( GLenum p, GLfloat v ) { (void)p;(void)v; }

void MTL_AssignExtensionPointers( void ) {
    qglMultiTexCoord2fARB = MTLAPI_MultiTexCoord2fARB;
    qglActiveTextureARB = MTLAPI_ActiveTextureARB;
    qglClientActiveTextureARB = MTLAPI_ClientActiveTextureARB;
    qglLockArraysEXT = MTLAPI_LockArraysEXT;
    qglUnlockArraysEXT = MTLAPI_UnlockArraysEXT;
    qglPNTrianglesiATI = MTLAPI_PNTrianglesiATI;   // present but Truform stays off via ext string
    qglPNTrianglesfATI = MTLAPI_PNTrianglesfATI;
}

// ---- textures ----
void qglGenTextures( GLsizei n, GLuint *out ) {
    for (int i=0;i<n;i++) {
        GLuint name = s_nextTexName++;
        MtlTexObj t = {}; t.minFilter=GL_LINEAR; t.magFilter=GL_LINEAR; t.wrapS=GL_REPEAT; t.wrapT=GL_REPEAT; t.dirty=true;
        s_textures[name]=t;
        out[i]=name;
    }
}
void qglDeleteTextures( GLsizei n, const GLuint *names ) {
    for (int i=0;i<n;i++) {
        GLuint nm=names[i];
        if (nm && s_textures.count(nm)) {
            if (s_boundTex[0]==nm) s_boundTex[0]=0;
            if (s_boundTex[1]==nm) s_boundTex[1]=0;
            s_textures.erase(nm);
        }
    }
}
void qglBindTexture( GLenum target, GLuint name ) {
    (void)target;
    s_boundTex[s_serverTexUnit] = name;
    if (name && !s_textures.count(name)) {
        MtlTexObj t = {}; t.minFilter=GL_LINEAR; t.magFilter=GL_LINEAR; t.wrapS=GL_REPEAT; t.wrapT=GL_REPEAT; t.dirty=true;
        s_textures[name]=t;
    }
}
static int glComponents( GLenum fmt ) {
    switch(fmt){ case GL_RGBA: case GL_RGBA8: case GL_BGRA: return 4;
                 case GL_RGB: case GL_RGB8: return 3;
                 case GL_LUMINANCE: case GL_ALPHA: return 1;
                 case GL_LUMINANCE_ALPHA: return 2; default: return 4; }
}
static void uploadRGBA( GLuint name, GLint w, GLint h, GLenum format, const void *pixels, bool mip ) {
    if (!name || !s_textures.count(name) || w<=0 || h<=0) return;
    MtlTexObj &t = s_textures[name];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:w height:h mipmapped:(mip?YES:NO)];
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    t.tex = [mtl_device newTextureWithDescriptor:td];
    // expand to RGBA8
    unsigned char *rgba = (unsigned char*)malloc((size_t)w*h*4);
    if (pixels) {
        int comp = glComponents(format);
        const unsigned char *src = (const unsigned char*)pixels;
        for (int i=0;i<w*h;i++) {
            unsigned char r=0,g=0,b=0,a=255;
            if (comp>=3){ r=src[i*comp+0]; g=src[i*comp+1]; b=src[i*comp+2]; if(comp>=4)a=src[i*comp+3]; }
            else { r=g=b=src[i*comp+0]; if(comp==2)a=src[i*comp+1]; }
            rgba[i*4+0]=r; rgba[i*4+1]=g; rgba[i*4+2]=b; rgba[i*4+3]=a;
        }
    } else {
        memset(rgba,255,(size_t)w*h*4);
    }
    [t.tex replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:rgba bytesPerRow:w*4];
    free(rgba);
    if (mip) {
        id<MTLCommandBuffer> cb=[mtl_queue commandBuffer];
        id<MTLBlitCommandEncoder> bl=[cb blitCommandEncoder];
        [bl generateMipmapsForTexture:t.tex];
        [bl endEncoding]; [cb commit];
    }
    t.dirty = true;
}
void qglTexImage2D( GLenum target, GLint level, GLint internalformat, GLsizei w, GLsizei h,
                    GLint border, GLenum format, GLenum type, const GLvoid *pixels ) {
    (void)target;(void)internalformat;(void)border;(void)type;
    if (level != 0) return; // mips generated automatically
    bool mip = true;
    GLuint name = s_boundTex[s_serverTexUnit];
    uploadRGBA(name, w, h, format, pixels, mip);
}
void qglTexSubImage2D( GLenum target, GLint level, GLint xoff, GLint yoff, GLsizei w, GLsizei h,
                       GLenum format, GLenum type, const GLvoid *pixels ) {
    (void)target;(void)type;
    if (level!=0) return;
    GLuint name=s_boundTex[s_serverTexUnit];
    if (!name||!s_textures.count(name)||!s_textures[name].tex||!pixels) return;
    int comp=glComponents(format);
    unsigned char *rgba=(unsigned char*)malloc((size_t)w*h*4);
    const unsigned char *src=(const unsigned char*)pixels;
    for (int i=0;i<w*h;i++){ unsigned char r=0,g=0,b=0,a=255;
        if(comp>=3){r=src[i*comp];g=src[i*comp+1];b=src[i*comp+2];if(comp>=4)a=src[i*comp+3];}
        else{r=g=b=src[i*comp];if(comp==2)a=src[i*comp+1];}
        rgba[i*4]=r;rgba[i*4+1]=g;rgba[i*4+2]=b;rgba[i*4+3]=a; }
    [s_textures[name].tex replaceRegion:MTLRegionMake2D(xoff,yoff,w,h) mipmapLevel:0 withBytes:rgba bytesPerRow:w*4];
    free(rgba);
}
void qglTexParameterf( GLenum target, GLenum pname, GLfloat param ) {
    (void)target; GLuint name=s_boundTex[s_serverTexUnit];
    if (!name||!s_textures.count(name)) return;
    MtlTexObj &t=s_textures[name];
    switch(pname){
        case GL_TEXTURE_MIN_FILTER: t.minFilter=(GLenum)param; break;
        case GL_TEXTURE_MAG_FILTER: t.magFilter=(GLenum)param; break;
        case GL_TEXTURE_WRAP_S: t.wrapS=(GLenum)param; break;
        case GL_TEXTURE_WRAP_T: t.wrapT=(GLenum)param; break;
    }
    t.dirty=true;
}
void qglTexParameterfv( GLenum target, GLenum pname, const GLfloat *params ) {
    qglTexParameterf(target,pname,params[0]);
}
void qglTexEnvf( GLenum target, GLenum pname, GLfloat param ) {
    (void)target;
    if (pname==GL_TEXTURE_ENV_MODE) s_texEnvMode[s_serverTexUnit]=(GLenum)param;
}

// ---- state ----
void qglEnable( GLenum c ) {
    switch(c){
        case GL_BLEND: s_blend=1; break;
        case GL_DEPTH_TEST: s_depthTest=1; break;
        case GL_CULL_FACE: s_cull=1; break;
        case GL_ALPHA_TEST: s_alphaTest=1; break;
        case GL_FOG: s_fog=1; break;
        case GL_TEXTURE_2D: s_texEnabled[s_serverTexUnit]=1; break;
        case GL_SCISSOR_TEST: s_scissor=1; break;
        case GL_STENCIL_TEST: s_stencil=1; break;
        case GL_POLYGON_OFFSET_FILL: s_polyOffset=1; break;
        default: break;
    }
}
void qglDisable( GLenum c ) {
    switch(c){
        case GL_BLEND: s_blend=0; break;
        case GL_DEPTH_TEST: s_depthTest=0; break;
        case GL_CULL_FACE: s_cull=0; break;
        case GL_ALPHA_TEST: s_alphaTest=0; break;
        case GL_FOG: s_fog=0; break;
        case GL_TEXTURE_2D: s_texEnabled[s_serverTexUnit]=0; break;
        case GL_SCISSOR_TEST: s_scissor=0; break;
        case GL_STENCIL_TEST: s_stencil=0; break;
        case GL_POLYGON_OFFSET_FILL: s_polyOffset=0; break;
        default: break;
    }
}
void qglBlendFunc( GLenum s, GLenum d ) { s_blendSrc=s; s_blendDst=d; }
void qglDepthFunc( GLenum f ) { s_depthFunc=f; }
void qglDepthMask( GLboolean m ) { s_depthMask=m?1:0; }
void qglColorMask( GLboolean r, GLboolean g, GLboolean b, GLboolean a ) { s_colorMask[0]=r;s_colorMask[1]=g;s_colorMask[2]=b;s_colorMask[3]=a; }
void qglCullFace( GLenum f ) { s_cullFace=f; }
void qglAlphaFunc( GLenum f, GLclampf ref ) { s_alphaFunc=f; s_alphaRef=ref; }
void qglShadeModel( GLenum m ) { (void)m; }
void qglDepthRange( GLclampd n, GLclampd f ) { s_depthRange[0]=n; s_depthRange[1]=f; }
void qglViewport( GLint x, GLint y, GLsizei w, GLsizei h ) { s_viewport[0]=x;s_viewport[1]=y;s_viewport[2]=w;s_viewport[3]=h; }
void qglScissor( GLint x, GLint y, GLsizei w, GLsizei h ) { s_scissorBox[0]=x;s_scissorBox[1]=y;s_scissorBox[2]=w;s_scissorBox[3]=h; }
void qglPolygonMode( GLenum face, GLenum mode ) { (void)face; s_polygonMode=mode; }
void qglPolygonOffset( GLfloat factor, GLfloat units ) { s_polyOffsetFactor=factor; s_polyOffsetUnits=units; }
void qglLineWidth( GLfloat w ) { (void)w; }
void qglHint( GLenum t, GLenum m ) { (void)t;(void)m; }
void qglClipPlane( GLenum p, const GLdouble *eq ) { (void)p;(void)eq; }

// fog
void qglFogf( GLenum pname, GLfloat p ) {
    switch(pname){ case GL_FOG_DENSITY: s_fogDensity=p; break; case GL_FOG_START: s_fogStart=p; break; case GL_FOG_END: s_fogEnd=p; break; }
}
void qglFogi( GLenum pname, GLint p ) { if (pname==GL_FOG_MODE) s_fogMode=(GLenum)p; }
void qglFogfv( GLenum pname, const GLfloat *p ) {
    if (pname==GL_FOG_COLOR) s_fogColor=(simd_float4){p[0],p[1],p[2],p[3]};
    else qglFogf(pname,p[0]);
}

// stencil
void qglStencilFunc( GLenum f, GLint ref, GLuint mask ) { s_stencilFunc=f; s_stencilRef=ref; s_stencilValMask=mask; }
void qglStencilMask( GLuint m ) { s_stencilWriteMask=m; }
void qglStencilOp( GLenum f, GLenum zf, GLenum zp ) { s_stencilFail=f; s_stencilZFail=zf; s_stencilZPass=zp; }

// clears
void qglClearColor( GLclampf r, GLclampf g, GLclampf b, GLclampf a ) { s_clearColor=(simd_float4){r,g,b,a}; }
void qglClearDepth( GLclampd d ) { s_clearDepth=d; }
void qglClearStencil( GLint s ) { s_clearStencil=s; }
void qglClear( GLbitfield mask ) {
    // apply as a load-clear on the next encoder: end the current pass and
    // mark the requested attachments to clear when the next one opens.
    MTL_EndEncoder();
    if (mask & GL_COLOR_BUFFER_BIT)   s_pendColorLoad = MTLLoadActionClear;
    if (mask & GL_DEPTH_BUFFER_BIT)   s_pendDepthLoad = MTLLoadActionClear;
    if (mask & GL_STENCIL_BUFFER_BIT) s_pendStencilLoad = MTLLoadActionClear;
    MTL_Encoder(); // open immediately so the clear is realised even with no draw
}

// reads / queries
const GLubyte *qglGetString( GLenum name ) {
    switch(name){
        case GL_VENDOR: return (const GLubyte*)"Apple (Metal)";
        case GL_RENDERER: return (const GLubyte*)"RTCW Metal (GL1.x shim)";
        case GL_VERSION: return (const GLubyte*)"1.4 (Metal)";
        case GL_EXTENSIONS: return (const GLubyte*)"GL_ARB_multitexture GL_EXT_texture_env_add GL_EXT_compiled_vertex_array";
        default: return (const GLubyte*)"";
    }
}
void qglGetIntegerv( GLenum pname, GLint *p ) {
    switch(pname){
        case GL_MAX_TEXTURE_SIZE: *p = 16384; break;
        case GL_MAX_ACTIVE_TEXTURES_ARB: *p = 2; break;
        default: *p = 0; break;
    }
}
void qglGetFloatv( GLenum pname, GLfloat *p ) { (void)pname; p[0]=0; }
GLenum qglGetError( void ) { return GL_NO_ERROR; }
void qglFinish( void ) {
    MTL_EndEncoder();
    if (mtl_cmd) { [mtl_cmd commit]; [mtl_cmd waitUntilCompleted]; mtl_cmd=[mtl_queue commandBuffer]; }
}
void qglDrawBuffer( GLenum b ) { (void)b; }
void qglCallList( GLuint l ) { (void)l; }

// used only by the (editor-only) splines debug drawing; minimal.
void qglPointSize( GLfloat s ) { (void)s; }
void qglRasterPos3fv( const GLfloat *v ) { (void)v; }
void qglCallLists( GLsizei n, GLenum type, const GLvoid *lists ) { (void)n;(void)type;(void)lists; }

// screenshots: read back from the current drawable's texture (RGBA/BGRA).
void qglReadPixels( GLint x, GLint y, GLsizei w, GLsizei h, GLenum format, GLenum type, GLvoid *pixels ) {
    (void)type;
    if (!pixels || w<=0 || h<=0) return;
    qglFinish();
    id<MTLTexture> src = mtl_drawable ? mtl_drawable.texture : nil;
    if (!src) { memset(pixels,0,(size_t)w*h*(format==GL_RGB?3:4)); return; }
    int flipY = mtl_drawHeight - (y + h);
    size_t bpr = (size_t)w*4;
    unsigned char *tmp=(unsigned char*)malloc(bpr*h);
    [src getBytes:tmp bytesPerRow:bpr fromRegion:MTLRegionMake2D(x, flipY<0?0:flipY, w, h) mipmapLevel:0];
    int outc = (format==GL_RGB)?3:4;
    unsigned char *dst=(unsigned char*)pixels;
    // texture is BGRA8; GL wants RGB(A), and bottom-up
    for (int row=0; row<h; row++) {
        const unsigned char *s = tmp + (size_t)(h-1-row)*bpr;
        unsigned char *d = dst + (size_t)row*w*outc;
        for (int i=0;i<w;i++){ d[i*outc+0]=s[i*4+2]; d[i*outc+1]=s[i*4+1]; d[i*outc+2]=s[i*4+0]; if(outc==4)d[i*outc+3]=s[i*4+3]; }
    }
    free(tmp);
}

} // extern "C"

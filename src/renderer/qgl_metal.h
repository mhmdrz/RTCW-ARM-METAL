/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

qgl_metal.h -- GL 1.x type/enum/prototype surface for the Metal backend.

Included by qgl.h when USE_METAL is defined. Provides a self-contained
replacement for <OpenGL/gl.h> + qgl_linked.h: GL base types, the GL_* enum
constants the renderer passes as arguments, and prototypes for the qgl*
entry points implemented by the GL-1.x-on-Metal shim in src/metal/mtl_gl.mm.
No system OpenGL headers are used (iOS has none; macOS renders via Metal).
===========================================================================
*/
#ifndef __QGL_METAL_H__
#define __QGL_METAL_H__

#ifndef APIENTRY
#define APIENTRY
#endif
#ifndef WINAPI
#define WINAPI
#endif

/* ---- GL base types ---- */
typedef unsigned int    GLenum;
typedef unsigned char   GLboolean;
typedef unsigned int    GLbitfield;
typedef void            GLvoid;
typedef signed char     GLbyte;
typedef short           GLshort;
typedef int             GLint;
typedef int             GLsizei;
typedef unsigned char   GLubyte;
typedef unsigned short  GLushort;
typedef unsigned int    GLuint;
typedef float           GLfloat;
typedef float           GLclampf;
typedef double          GLdouble;
typedef double          GLclampd;
typedef char            GLchar;

/* ---- GL enum constants (values from the macOS OpenGL headers) ---- */
#define GL_ACTIVE_TEXTURE_ARB                        0x84E0
#define GL_ADD                                       0x0104
#define GL_ALPHA_TEST                                0x0BC0
#define GL_ALWAYS                                    0x0207
#define GL_BACK                                      0x0405
#define GL_BACK_LEFT                                 0x0402
#define GL_BACK_RIGHT                                0x0403
#define GL_BLEND                                     0x0BE2
#define GL_CLAMP                                     0x2900
#define GL_CLIENT_ACTIVE_TEXTURE_ARB                 0x84E1
#define GL_CLIP_PLANE0                               0x3000
#define GL_COLOR_ARRAY                               0x8076
#define GL_COLOR_BUFFER_BIT                          0x00004000
#define GL_COMPRESSED_RGB_S3TC_DXT1_EXT              0x83F0
#define GL_COMPRESSED_RGBA_S3TC_DXT1_EXT             0x83F1
#define GL_COMPRESSED_RGBA_S3TC_DXT3_EXT             0x83F2
#define GL_COMPRESSED_RGBA_S3TC_DXT5_EXT             0x83F3
#define GL_CULL_FACE                                 0x0B44
#define GL_DECAL                                     0x2101
#define GL_DECR                                      0x1E03
#define GL_DEPTH_BUFFER_BIT                          0x00000100
#define GL_DEPTH_COMPONENT                           0x1902
#define GL_DEPTH_TEST                                0x0B71
#define GL_DONT_CARE                                 0x1100
#define GL_DST_ALPHA                                 0x0304
#define GL_DST_COLOR                                 0x0306
#define GL_EQUAL                                     0x0202
#define GL_EXP                                       0x0800
#define GL_EXTENSIONS                                0x1F03
#define GL_EYE_PLANE                                 0x2502
#define GL_EYE_PLANE_ABSOLUTE_NV                     0x855C
#define GL_EYE_RADIAL_NV                             0x855B
#define GL_FALSE                                     0
#define GL_FILL                                      0x1B02
#define GL_FLAT                                      0x1D00
#define GL_FLOAT                                     0x1406
#define GL_FOG                                       0x0B60
#define GL_FOG_COLOR                                 0x0B66
#define GL_FOG_DENSITY                               0x0B62
#define GL_FOG_DISTANCE_MODE_NV                      0x855A
#define GL_FOG_END                                   0x0B64
#define GL_FOG_HINT                                  0x0C54
#define GL_FOG_MODE                                  0x0B65
#define GL_FOG_START                                 0x0B63
#define GL_FRONT                                     0x0404
#define GL_FRONT_AND_BACK                            0x0408
#define GL_GEQUAL                                    0x0206
#define GL_GREATER                                   0x0204
#define GL_INCR                                      0x1E02
#define GL_INVALID_ENUM                              0x0500
#define GL_INVALID_OPERATION                         0x0502
#define GL_INVALID_VALUE                             0x0501
#define GL_KEEP                                      0x1E00
#define GL_LEQUAL                                    0x0203
#define GL_LESS                                      0x0201
#define GL_LINE                                      0x1B01
#define GL_LINEAR                                    0x2601
#define GL_LINEAR_MIPMAP_LINEAR                      0x2703
#define GL_LINEAR_MIPMAP_NEAREST                     0x2701
#define GL_LINES                                     0x0001
#define GL_POINTS                                    0x0000
#define GL_LINE_LOOP                                 0x0002
#define GL_LINE_STRIP                                0x0003
#define GL_TRIANGLE_FAN                              0x0006
/* extra enums referenced by the Metal shim itself */
#define GL_NEVER                                     0x0200
#define GL_INVERT                                    0x150A
#define GL_EXP2                                      0x0801
#define GL_UNSIGNED_SHORT                            0x1403
#define GL_BGRA                                      0x80E1
#define GL_ALPHA                                     0x1906
#define GL_LUMINANCE                                 0x1909
#define GL_LUMINANCE_ALPHA                           0x190A
#define GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT            0x84FF
#define GL_MAX_TEXTURE_SIZE                          0x0D33
#define GL_MODELVIEW                                 0x1700
#define GL_MODULATE                                  0x2100
#define GL_NEAREST                                   0x2600
#define GL_NEAREST_MIPMAP_LINEAR                     0x2702
#define GL_NEAREST_MIPMAP_NEAREST                    0x2700
#define GL_NO_ERROR                                  0
#define GL_NORMAL_ARRAY                              0x8075
#define GL_NOTEQUAL                                  0x0205
#define GL_ONE                                       1
#define GL_ONE_MINUS_DST_ALPHA                       0x0305
#define GL_ONE_MINUS_DST_COLOR                       0x0307
#define GL_ONE_MINUS_SRC_ALPHA                       0x0303
#define GL_ONE_MINUS_SRC_COLOR                       0x0301
#define GL_OUT_OF_MEMORY                             0x0505
#define GL_POLYGON                                   0x0009
#define GL_POLYGON_OFFSET_FILL                       0x8037
#define GL_PROJECTION                                0x1701
#define GL_QUADS                                     0x0007
#define GL_RENDERER                                  0x1F01
#define GL_REPEAT                                    0x2901
#define GL_REPLACE                                   0x1E01
#define GL_RGB                                       0x1907
#define GL_RGB5                                      0x8050
#define GL_RGB8                                      0x8051
#define GL_RGBA                                      0x1908
#define GL_RGBA4                                     0x8056
#define GL_RGBA8                                     0x8058
#define GL_SCISSOR_TEST                              0x0C11
#define GL_SMOOTH                                    0x1D01
#define GL_SRC_ALPHA                                 0x0302
#define GL_SRC_ALPHA_SATURATE                        0x0308
#define GL_SRC_COLOR                                 0x0300
#define GL_STACK_OVERFLOW                            0x0503
#define GL_STACK_UNDERFLOW                           0x0504
#define GL_STENCIL_BUFFER_BIT                        0x00000400
#define GL_STENCIL_INDEX                             0x1901
#define GL_STENCIL_TEST                              0x0B90
#define GL_TEXTURE_2D                                0x0DE1
#define GL_TEXTURE_BORDER_COLOR                      0x1004
#define GL_TEXTURE_COORD_ARRAY                       0x8078
#define GL_TEXTURE_ENV                               0x2300
#define GL_TEXTURE_ENV_MODE                          0x2200
#define GL_TEXTURE_MAG_FILTER                        0x2800
#define GL_TEXTURE_MAX_ANISOTROPY_EXT                0x84FE
#define GL_TEXTURE_MIN_FILTER                        0x2801
#define GL_TEXTURE_WRAP_S                            0x2802
#define GL_TEXTURE_WRAP_T                            0x2803
#define GL_TEXTURE0_ARB                              0x84C0
#define GL_TEXTURE1_ARB                              0x84C1
#define GL_TEXTURE2_ARB                              0x84C2
#define GL_TEXTURE3_ARB                              0x84C3
#define GL_TRIANGLE_STRIP                            0x0005
#define GL_TRIANGLES                                 0x0004
#define GL_TRUE                                      1
#define GL_UNSIGNED_BYTE                             0x1401
#define GL_UNSIGNED_INT                              0x1405
#define GL_VENDOR                                    0x1F00
#define GL_VERSION                                   0x1F02
#define GL_VERSION_1_2                               1
#define GL_VERTEX_ARRAY                              0x8074
#define GL_ZERO                                      0
#define GL_MAX_ACTIVE_TEXTURES_ARB                   0x84E2
#define GL_MAX_TEXTURE_UNITS_ARB                     0x84E2
#define GL_RGB_S3TC                                  0x83A0
#define GL_RGB4_S3TC                                 0x83A1
#define GL_PN_TRIANGLES_ATI                          0x87F0
#define GL_MAX_PN_TRIANGLES_TESSELATION_LEVEL_ATI    0x87F1
#define GL_PN_TRIANGLES_POINT_MODE_ATI               0x87F2
#define GL_PN_TRIANGLES_NORMAL_MODE_ATI              0x87F3
#define GL_PN_TRIANGLES_TESSELATION_LEVEL_ATI        0x87F4
#define GL_PN_TRIANGLES_POINT_MODE_LINEAR_ATI        0x87F5
#define GL_PN_TRIANGLES_POINT_MODE_CUBIC_ATI         0x87F6
#define GL_PN_TRIANGLES_NORMAL_MODE_LINEAR_ATI       0x87F7
#define GL_PN_TRIANGLES_NORMAL_MODE_QUADRATIC_ATI    0x87F8

/* ---- multitexture / extension entry points (function pointers, assigned
        by the Metal shim; kept as pointers so the backend can null-check
        them exactly as in the GL build) ---- */
#ifdef __cplusplus
extern "C" {
#endif
extern void ( APIENTRY * qglMultiTexCoord2fARB )( GLenum texture, GLfloat s, GLfloat t );
extern void ( APIENTRY * qglActiveTextureARB )( GLenum texture );
extern void ( APIENTRY * qglClientActiveTextureARB )( GLenum texture );
extern void ( APIENTRY * qglLockArraysEXT )( GLint, GLint );
extern void ( APIENTRY * qglUnlockArraysEXT )( void );
extern void ( APIENTRY * qglPNTrianglesiATI )( GLenum pname, GLint param );
extern void ( APIENTRY * qglPNTrianglesfATI )( GLenum pname, GLfloat param );

/* ---- core qgl* entry points (implemented in src/metal/mtl_gl.mm) ---- */
void qglAccum( GLenum op, GLfloat value );
void qglAlphaFunc( GLenum func, GLclampf ref );
GLboolean qglAreTexturesResident( GLsizei n, const GLuint *textures, GLboolean *residences );
void qglArrayElement( GLint i );
void qglBegin( GLenum mode );
void qglBindTexture( GLenum target, GLuint texture );
void qglBitmap( GLsizei width, GLsizei height, GLfloat xorig, GLfloat yorig, GLfloat xmove, GLfloat ymove, const GLubyte *bitmap );
void qglBlendFunc( GLenum sfactor, GLenum dfactor );
void qglCallList( GLuint list );
void qglCallLists( GLsizei n, GLenum type, const GLvoid *lists );
void qglClear( GLbitfield mask );
void qglClearAccum( GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha );
void qglClearColor( GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha );
void qglClearDepth( GLclampd depth );
void qglClearIndex( GLfloat c );
void qglClearStencil( GLint s );
void qglClipPlane( GLenum plane, const GLdouble *equation );
void qglColor3b( GLbyte red, GLbyte green, GLbyte blue );
void qglColor3bv( const GLbyte *v );
void qglColor3d( GLdouble red, GLdouble green, GLdouble blue );
void qglColor3dv( const GLdouble *v );
void qglColor3f( GLfloat red, GLfloat green, GLfloat blue );
void qglColor3fv( const GLfloat *v );
void qglColor3i( GLint red, GLint green, GLint blue );
void qglColor3iv( const GLint *v );
void qglColor3s( GLshort red, GLshort green, GLshort blue );
void qglColor3sv( const GLshort *v );
void qglColor3ub( GLubyte red, GLubyte green, GLubyte blue );
void qglColor3ubv( const GLubyte *v );
void qglColor3ui( GLuint red, GLuint green, GLuint blue );
void qglColor3uiv( const GLuint *v );
void qglColor3us( GLushort red, GLushort green, GLushort blue );
void qglColor3usv( const GLushort *v );
void qglColor4b( GLbyte red, GLbyte green, GLbyte blue, GLbyte alpha );
void qglColor4bv( const GLbyte *v );
void qglColor4d( GLdouble red, GLdouble green, GLdouble blue, GLdouble alpha );
void qglColor4dv( const GLdouble *v );
void qglColor4f( GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha );
void qglColor4fv( const GLfloat *v );
void qglColor4i( GLint red, GLint green, GLint blue, GLint alpha );
void qglColor4iv( const GLint *v );
void qglColor4s( GLshort red, GLshort green, GLshort blue, GLshort alpha );
void qglColor4sv( const GLshort *v );
void qglColor4ub( GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha );
void qglColor4ubv( const GLubyte *v );
void qglColor4ui( GLuint red, GLuint green, GLuint blue, GLuint alpha );
void qglColor4uiv( const GLuint *v );
void qglColor4us( GLushort red, GLushort green, GLushort blue, GLushort alpha );
void qglColor4usv( const GLushort *v );
void qglColorMask( GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha );
void qglColorMaterial( GLenum face, GLenum mode );
void qglColorPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *pointer );
void qglCopyPixels( GLint x, GLint y, GLsizei width, GLsizei height, GLenum type );
void qglCopyTexImage1D( GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLint border );
void qglCopyTexImage2D( GLenum target, GLint level, GLenum internalFormat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border );
void qglCopyTexSubImage1D( GLenum target, GLint level, GLint xoffset, GLint x, GLint y, GLsizei width );
void qglCopyTexSubImage2D( GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height );
void qglCullFace( GLenum mode );
void qglDeleteLists( GLuint list, GLsizei range );
void qglDeleteTextures( GLsizei n, const GLuint *textures );
void qglDepthFunc( GLenum func );
void qglDepthMask( GLboolean flag );
void qglDepthRange( GLclampd zNear, GLclampd zFar );
void qglDisable( GLenum cap );
void qglDisableClientState( GLenum array );
void qglDrawArrays( GLenum mode, GLint first, GLsizei count );
void qglDrawBuffer( GLenum mode );
void qglDrawElements( GLenum mode, GLsizei count, GLenum type, const GLvoid *indices );
void qglDrawPixels( GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels );
void qglEdgeFlag( GLboolean flag );
void qglEdgeFlagPointer( GLsizei stride, const GLvoid *pointer );
void qglEdgeFlagv( const GLboolean *flag );
void qglEnable( GLenum cap );
void qglEnableClientState( GLenum array );
void qglEnd( void );
void qglEndList( void );
void qglEvalCoord1d( GLdouble u );
void qglEvalCoord1dv( const GLdouble *u );
void qglEvalCoord1f( GLfloat u );
void qglEvalCoord1fv( const GLfloat *u );
void qglEvalCoord2d( GLdouble u, GLdouble v );
void qglEvalCoord2dv( const GLdouble *u );
void qglEvalCoord2f( GLfloat u, GLfloat v );
void qglEvalCoord2fv( const GLfloat *u );
void qglEvalMesh1( GLenum mode, GLint i1, GLint i2 );
void qglEvalMesh2( GLenum mode, GLint i1, GLint i2, GLint j1, GLint j2 );
void qglEvalPoint1( GLint i );
void qglEvalPoint2( GLint i, GLint j );
void qglFeedbackBuffer( GLsizei size, GLenum type, GLfloat *buffer );
void qglFinish( void );
void qglFlush( void );
void qglFogf( GLenum pname, GLfloat param );
void qglFogfv( GLenum pname, const GLfloat *params );
void qglFogi( GLenum pname, GLint param );
void qglFogiv( GLenum pname, const GLint *params );
void qglFrontFace( GLenum mode );
void qglFrustum( GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar );
GLuint qglGenLists( GLsizei range );
void qglGenTextures( GLsizei n, GLuint *textures );
void qglGetBooleanv( GLenum pname, GLboolean *params );
void qglGetClipPlane( GLenum plane, GLdouble *equation );
void qglGetDoublev( GLenum pname, GLdouble *params );
GLenum qglGetError( void );
void qglGetFloatv( GLenum pname, GLfloat *params );
void qglGetIntegerv( GLenum pname, GLint *params );
void qglGetLightfv( GLenum light, GLenum pname, GLfloat *params );
void qglGetLightiv( GLenum light, GLenum pname, GLint *params );
void qglGetMapdv( GLenum target, GLenum query, GLdouble *v );
void qglGetMapfv( GLenum target, GLenum query, GLfloat *v );
void qglGetMapiv( GLenum target, GLenum query, GLint *v );
void qglGetMaterialfv( GLenum face, GLenum pname, GLfloat *params );
void qglGetMaterialiv( GLenum face, GLenum pname, GLint *params );
void qglGetPixelMapfv( GLenum map, GLfloat *values );
void qglGetPixelMapuiv( GLenum map, GLuint *values );
void qglGetPixelMapusv( GLenum map, GLushort *values );
void qglGetPointerv( GLenum pname, GLvoid* *params );
void qglGetPolygonStipple( GLubyte *mask );
const GLubyte * qglGetString(GLenum name);
void qglGetTexEnvfv( GLenum target, GLenum pname, GLfloat *params );
void qglGetTexEnviv( GLenum target, GLenum pname, GLint *params );
void qglGetTexGendv( GLenum coord, GLenum pname, GLdouble *params );
void qglGetTexGenfv( GLenum coord, GLenum pname, GLfloat *params );
void qglGetTexGeniv( GLenum coord, GLenum pname, GLint *params );
void qglGetTexImage( GLenum target, GLint level, GLenum format, GLenum type, GLvoid *pixels );
void qglGetTexLevelParameterfv( GLenum target, GLint level, GLenum pname, GLfloat *params );
void qglGetTexLevelParameteriv( GLenum target, GLint level, GLenum pname, GLint *params );
void qglGetTexParameterfv( GLenum target, GLenum pname, GLfloat *params );
void qglGetTexParameteriv( GLenum target, GLenum pname, GLint *params );
void qglHint( GLenum target, GLenum mode );
void qglIndexMask( GLuint mask );
void qglIndexPointer( GLenum type, GLsizei stride, const GLvoid *pointer );
void qglIndexd( GLdouble c );
void qglIndexdv( const GLdouble *c );
void qglIndexf( GLfloat c );
void qglIndexfv( const GLfloat *c );
void qglIndexi( GLint c );
void qglIndexiv( const GLint *c );
void qglIndexs( GLshort c );
void qglIndexsv( const GLshort *c );
void qglIndexub( GLubyte c );
void qglIndexubv( const GLubyte *c );
void qglInitNames( void );
void qglInterleavedArrays( GLenum format, GLsizei stride, const GLvoid *pointer );
GLboolean qglIsEnabled( GLenum cap );
GLboolean qglIsList( GLuint list );
GLboolean qglIsTexture( GLuint texture );
void qglLightModelf( GLenum pname, GLfloat param );
void qglLightModelfv( GLenum pname, const GLfloat *params );
void qglLightModeli( GLenum pname, GLint param );
void qglLightModeliv( GLenum pname, const GLint *params );
void qglLightf( GLenum light, GLenum pname, GLfloat param );
void qglLightfv( GLenum light, GLenum pname, const GLfloat *params );
void qglLighti( GLenum light, GLenum pname, GLint param );
void qglLightiv( GLenum light, GLenum pname, const GLint *params );
void qglLineStipple( GLint factor, GLushort pattern );
void qglLineWidth( GLfloat width );
void qglListBase( GLuint base );
void qglLoadIdentity( void );
void qglLoadMatrixd( const GLdouble *m );
void qglLoadMatrixf( const GLfloat *m );
void qglLoadName( GLuint name );
void qglLogicOp( GLenum opcode );
void qglMap1d( GLenum target, GLdouble u1, GLdouble u2, GLint stride, GLint order, const GLdouble *points );
void qglMap1f( GLenum target, GLfloat u1, GLfloat u2, GLint stride, GLint order, const GLfloat *points );
void qglMap2d( GLenum target, GLdouble u1, GLdouble u2, GLint ustride, GLint uorder, GLdouble v1, GLdouble v2, GLint vstride, GLint vorder, const GLdouble *points );
void qglMap2f( GLenum target, GLfloat u1, GLfloat u2, GLint ustride, GLint uorder, GLfloat v1, GLfloat v2, GLint vstride, GLint vorder, const GLfloat *points );
void qglMapGrid1d( GLint un, GLdouble u1, GLdouble u2 );
void qglMapGrid1f( GLint un, GLfloat u1, GLfloat u2 );
void qglMapGrid2d( GLint un, GLdouble u1, GLdouble u2, GLint vn, GLdouble v1, GLdouble v2 );
void qglMapGrid2f( GLint un, GLfloat u1, GLfloat u2, GLint vn, GLfloat v1, GLfloat v2 );
void qglMaterialf( GLenum face, GLenum pname, GLfloat param );
void qglMaterialfv( GLenum face, GLenum pname, const GLfloat *params );
void qglMateriali( GLenum face, GLenum pname, GLint param );
void qglMaterialiv( GLenum face, GLenum pname, const GLint *params );
void qglMatrixMode( GLenum mode );
void qglMultMatrixd( const GLdouble *m );
void qglMultMatrixf( const GLfloat *m );
void qglNewList( GLuint list, GLenum mode );
void qglNormal3b( GLbyte nx, GLbyte ny, GLbyte nz );
void qglNormal3bv( const GLbyte *v );
void qglNormal3d( GLdouble nx, GLdouble ny, GLdouble nz );
void qglNormal3dv( const GLdouble *v );
void qglNormal3f( GLfloat nx, GLfloat ny, GLfloat nz );
void qglNormal3fv( const GLfloat *v );
void qglNormal3i( GLint nx, GLint ny, GLint nz );
void qglNormal3iv( const GLint *v );
void qglNormal3s( GLshort nx, GLshort ny, GLshort nz );
void qglNormal3sv( const GLshort *v );
void qglNormalPointer( GLenum type, GLsizei stride, const GLvoid *pointer );
void qglOrtho( GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar );
void qglPassThrough( GLfloat token );
void qglPixelMapfv( GLenum map, GLsizei mapsize, const GLfloat *values );
void qglPixelMapuiv( GLenum map, GLsizei mapsize, const GLuint *values );
void qglPixelMapusv( GLenum map, GLsizei mapsize, const GLushort *values );
void qglPixelStoref( GLenum pname, GLfloat param );
void qglPixelStorei( GLenum pname, GLint param );
void qglPixelTransferf( GLenum pname, GLfloat param );
void qglPixelTransferi( GLenum pname, GLint param );
void qglPixelZoom( GLfloat xfactor, GLfloat yfactor );
void qglPointSize( GLfloat size );
void qglPolygonMode( GLenum face, GLenum mode );
void qglPolygonOffset( GLfloat factor, GLfloat units );
void qglPolygonStipple( const GLubyte *mask );
void qglPopAttrib( void );
void qglPopClientAttrib( void );
void qglPopMatrix( void );
void qglPopName( void );
void qglPrioritizeTextures( GLsizei n, const GLuint *textures, const GLclampf *priorities );
void qglPushAttrib( GLbitfield mask );
void qglPushClientAttrib( GLbitfield mask );
void qglPushMatrix( void );
void qglPushName( GLuint name );
void qglRasterPos2d( GLdouble x, GLdouble y );
void qglRasterPos2dv( const GLdouble *v );
void qglRasterPos2f( GLfloat x, GLfloat y );
void qglRasterPos2fv( const GLfloat *v );
void qglRasterPos2i( GLint x, GLint y );
void qglRasterPos2iv( const GLint *v );
void qglRasterPos2s( GLshort x, GLshort y );
void qglRasterPos2sv( const GLshort *v );
void qglRasterPos3d( GLdouble x, GLdouble y, GLdouble z );
void qglRasterPos3dv( const GLdouble *v );
void qglRasterPos3f( GLfloat x, GLfloat y, GLfloat z );
void qglRasterPos3fv( const GLfloat *v );
void qglRasterPos3i( GLint x, GLint y, GLint z );
void qglRasterPos3iv( const GLint *v );
void qglRasterPos3s( GLshort x, GLshort y, GLshort z );
void qglRasterPos3sv( const GLshort *v );
void qglRasterPos4d( GLdouble x, GLdouble y, GLdouble z, GLdouble w );
void qglRasterPos4dv( const GLdouble *v );
void qglRasterPos4f( GLfloat x, GLfloat y, GLfloat z, GLfloat w );
void qglRasterPos4fv( const GLfloat *v );
void qglRasterPos4i( GLint x, GLint y, GLint z, GLint w );
void qglRasterPos4iv( const GLint *v );
void qglRasterPos4s( GLshort x, GLshort y, GLshort z, GLshort w );
void qglRasterPos4sv( const GLshort *v );
void qglReadBuffer( GLenum mode );
void qglReadPixels( GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, GLvoid *pixels );
void qglRectd( GLdouble x1, GLdouble y1, GLdouble x2, GLdouble y2 );
void qglRectdv( const GLdouble *v1, const GLdouble *v2 );
void qglRectf( GLfloat x1, GLfloat y1, GLfloat x2, GLfloat y2 );
void qglRectfv( const GLfloat *v1, const GLfloat *v2 );
void qglRecti( GLint x1, GLint y1, GLint x2, GLint y2 );
void qglRectiv( const GLint *v1, const GLint *v2 );
void qglRects( GLshort x1, GLshort y1, GLshort x2, GLshort y2 );
void qglRectsv( const GLshort *v1, const GLshort *v2 );
GLint qglRenderMode( GLenum mode );
void qglRotated( GLdouble angle, GLdouble x, GLdouble y, GLdouble z );
void qglRotatef( GLfloat angle, GLfloat x, GLfloat y, GLfloat z );
void qglScaled( GLdouble x, GLdouble y, GLdouble z );
void qglScalef( GLfloat x, GLfloat y, GLfloat z );
void qglScissor( GLint x, GLint y, GLsizei width, GLsizei height );
void qglSelectBuffer( GLsizei size, GLuint *buffer );
void qglShadeModel( GLenum mode );
void qglStencilFunc( GLenum func, GLint ref, GLuint mask );
void qglStencilMask( GLuint mask );
void qglStencilOp( GLenum fail, GLenum zfail, GLenum zpass );
void qglTexCoord1d( GLdouble s );
void qglTexCoord1dv( const GLdouble *v );
void qglTexCoord1f( GLfloat s );
void qglTexCoord1fv( const GLfloat *v );
void qglTexCoord1i( GLint s );
void qglTexCoord1iv( const GLint *v );
void qglTexCoord1s( GLshort s );
void qglTexCoord1sv( const GLshort *v );
void qglTexCoord2d( GLdouble s, GLdouble t );
void qglTexCoord2dv( const GLdouble *v );
void qglTexCoord2f( GLfloat s, GLfloat t );
void qglTexCoord2fv( const GLfloat *v );
void qglTexCoord2i( GLint s, GLint t );
void qglTexCoord2iv( const GLint *v );
void qglTexCoord2s( GLshort s, GLshort t );
void qglTexCoord2sv( const GLshort *v );
void qglTexCoord3d( GLdouble s, GLdouble t, GLdouble r );
void qglTexCoord3dv( const GLdouble *v );
void qglTexCoord3f( GLfloat s, GLfloat t, GLfloat r );
void qglTexCoord3fv( const GLfloat *v );
void qglTexCoord3i( GLint s, GLint t, GLint r );
void qglTexCoord3iv( const GLint *v );
void qglTexCoord3s( GLshort s, GLshort t, GLshort r );
void qglTexCoord3sv( const GLshort *v );
void qglTexCoord4d( GLdouble s, GLdouble t, GLdouble r, GLdouble q );
void qglTexCoord4dv( const GLdouble *v );
void qglTexCoord4f( GLfloat s, GLfloat t, GLfloat r, GLfloat q );
void qglTexCoord4fv( const GLfloat *v );
void qglTexCoord4i( GLint s, GLint t, GLint r, GLint q );
void qglTexCoord4iv( const GLint *v );
void qglTexCoord4s( GLshort s, GLshort t, GLshort r, GLshort q );
void qglTexCoord4sv( const GLshort *v );
void qglTexCoordPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *pointer );
void qglTexEnvf( GLenum target, GLenum pname, GLfloat param );
void qglTexEnvfv( GLenum target, GLenum pname, const GLfloat *params );
void qglTexEnvi( GLenum target, GLenum pname, GLint param );
void qglTexEnviv( GLenum target, GLenum pname, const GLint *params );
void qglTexGend( GLenum coord, GLenum pname, GLdouble param );
void qglTexGendv( GLenum coord, GLenum pname, const GLdouble *params );
void qglTexGenf( GLenum coord, GLenum pname, GLfloat param );
void qglTexGenfv( GLenum coord, GLenum pname, const GLfloat *params );
void qglTexGeni( GLenum coord, GLenum pname, GLint param );
void qglTexGeniv( GLenum coord, GLenum pname, const GLint *params );
void qglTexImage1D( GLenum target, GLint level, GLint internalformat, GLsizei width, GLint border, GLenum format, GLenum type, const GLvoid *pixels );
void qglTexImage2D( GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *pixels );
void qglTexParameterf( GLenum target, GLenum pname, GLfloat param );
void qglTexParameterfv( GLenum target, GLenum pname, const GLfloat *params );
void qglTexParameteri( GLenum target, GLenum pname, GLint param );
void qglTexParameteriv( GLenum target, GLenum pname, const GLint *params );
void qglTexSubImage1D( GLenum target, GLint level, GLint xoffset, GLsizei width, GLenum format, GLenum type, const GLvoid *pixels );
void qglTexSubImage2D( GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *pixels );
void qglTranslated( GLdouble x, GLdouble y, GLdouble z );
void qglTranslatef( GLfloat x, GLfloat y, GLfloat z );
void qglVertex2d( GLdouble x, GLdouble y );
void qglVertex2dv( const GLdouble *v );
void qglVertex2f( GLfloat x, GLfloat y );
void qglVertex2fv( const GLfloat *v );
void qglVertex2i( GLint x, GLint y );
void qglVertex2iv( const GLint *v );
void qglVertex2s( GLshort x, GLshort y );
void qglVertex2sv( const GLshort *v );
void qglVertex3d( GLdouble x, GLdouble y, GLdouble z );
void qglVertex3dv( const GLdouble *v );
void qglVertex3f( GLfloat x, GLfloat y, GLfloat z );
void qglVertex3fv( const GLfloat *v );
void qglVertex3i( GLint x, GLint y, GLint z );
void qglVertex3iv( const GLint *v );
void qglVertex3s( GLshort x, GLshort y, GLshort z );
void qglVertex3sv( const GLshort *v );
void qglVertex4d( GLdouble x, GLdouble y, GLdouble z, GLdouble w );
void qglVertex4dv( const GLdouble *v );
void qglVertex4f( GLfloat x, GLfloat y, GLfloat z, GLfloat w );
void qglVertex4fv( const GLfloat *v );
void qglVertex4i( GLint x, GLint y, GLint z, GLint w );
void qglVertex4iv( const GLint *v );
void qglVertex4s( GLshort x, GLshort y, GLshort z, GLshort w );
void qglVertex4sv( const GLshort *v );
void qglVertexPointer( GLint size, GLenum type, GLsizei stride, const GLvoid *pointer );
void qglViewport( GLint x, GLint y, GLsizei width, GLsizei height );
#ifdef __cplusplus
}
#endif

#endif // __QGL_METAL_H__

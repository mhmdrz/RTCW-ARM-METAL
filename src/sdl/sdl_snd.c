/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

SDL2 audio backend for the modern macOS (arm64) port. Replaces the OSS
code in unix/linux_snd.c. Implements the classic Quake DMA ring-buffer
model: the engine mixes 16-bit stereo samples into dma.buffer, and the
SDL audio callback streams them out, advancing the play cursor.
===========================================================================
*/

#include <SDL.h>
#include "../game/q_shared.h"
#include "../qcommon/qcommon.h"
#include "../client/snd_local.h"

extern dma_t dma;
extern cvar_t *s_khz;

static SDL_AudioDeviceID audioDevice = 0;
static int dmapos = 0;       // play cursor, in samples (not sample pairs)
static int dmasize = 0;      // size of dma.buffer in bytes

/*
===============
SDL audio callback: copy from the mix buffer (dma.buffer) into SDL's stream.
===============
*/
static void SNDDMA_AudioCallback( void *userdata, Uint8 *stream, int len ) {
	int pos = ( dmapos * ( dma.samplebits / 8 ) );
	int tobufend;
	int len1, len2;

	if ( !dma.buffer || dmasize <= 0 ) {
		memset( stream, 0, len );
		return;
	}

	if ( pos >= dmasize ) {
		pos = 0;
	}

	tobufend = dmasize - pos;
	len1 = len;
	len2 = 0;
	if ( len1 > tobufend ) {
		len1 = tobufend;
		len2 = len - len1;
	}

	memcpy( stream, dma.buffer + pos, len1 );
	if ( len2 > 0 ) {
		memcpy( stream + len1, dma.buffer, len2 );
		dmapos = ( len2 / ( dma.samplebits / 8 ) );
	} else {
		dmapos += ( len1 / ( dma.samplebits / 8 ) );
	}

	if ( dmapos >= dma.samples ) {
		dmapos = dmapos % dma.samples;
	}
}

/*
===============
SNDDMA_Init
===============
*/
qboolean SNDDMA_Init( void ) {
	SDL_AudioSpec desired, obtained;
	int khz;

	if ( audioDevice != 0 ) {
		return qtrue;
	}

	if ( SDL_WasInit( SDL_INIT_AUDIO ) == 0 ) {
		if ( SDL_InitSubSystem( SDL_INIT_AUDIO ) < 0 ) {
			Com_Printf( "SDL_InitSubSystem(AUDIO) failed: %s\n", SDL_GetError() );
			return qfalse;
		}
	}

	if ( !s_khz ) {
		s_khz = Cvar_Get( "s_khz", "22", CVAR_ARCHIVE );
	}
	khz = s_khz->integer;

	memset( &desired, 0, sizeof( desired ) );
	if ( khz >= 44 ) {
		desired.freq = 44100;
	} else if ( khz >= 22 ) {
		desired.freq = 22050;
	} else {
		desired.freq = 11025;
	}
	desired.format = AUDIO_S16SYS;
	desired.channels = 2;
	desired.samples = 1024;         // callback granularity
	desired.callback = SNDDMA_AudioCallback;

	audioDevice = SDL_OpenAudioDevice( NULL, 0, &desired, &obtained,
									   SDL_AUDIO_ALLOW_FREQUENCY_CHANGE );
	if ( audioDevice == 0 ) {
		Com_Printf( "SDL_OpenAudioDevice failed: %s\n", SDL_GetError() );
		return qfalse;
	}

	memset( &dma, 0, sizeof( dma ) );
	dma.channels = obtained.channels;
	dma.samplebits = SDL_AUDIO_BITSIZE( obtained.format );
	dma.speed = obtained.freq;
	// total mix buffer: a generous power-of-two number of sample slots
	dma.samples = 0x8000 * obtained.channels;   // sample slots (mono samples)
	dma.submission_chunk = 1;
	dmasize = dma.samples * ( dma.samplebits / 8 );
	dma.buffer = calloc( 1, dmasize );
	if ( !dma.buffer ) {
		Com_Printf( "SNDDMA_Init: out of memory for mix buffer\n" );
		SDL_CloseAudioDevice( audioDevice );
		audioDevice = 0;
		return qfalse;
	}
	dmapos = 0;

	SDL_PauseAudioDevice( audioDevice, 0 );     // start playback

	Com_Printf( "------- SDL2 Sound Initialization -------\n" );
	Com_Printf( "...%d Hz, %d-bit, %d channels\n", dma.speed, dma.samplebits, dma.channels );

	return qtrue;
}

/*
===============
SNDDMA_GetDMAPos
===============
*/
int SNDDMA_GetDMAPos( void ) {
	return dmapos;
}

/*
===============
SNDDMA_Shutdown
===============
*/
void SNDDMA_Shutdown( void ) {
	if ( audioDevice != 0 ) {
		SDL_CloseAudioDevice( audioDevice );
		audioDevice = 0;
	}
	if ( dma.buffer ) {
		free( dma.buffer );
		dma.buffer = NULL;
	}
	dmasize = 0;
	dmapos = 0;
}

/*
===============
SNDDMA_BeginPainting
===============
*/
void SNDDMA_BeginPainting( void ) {
	if ( audioDevice != 0 ) {
		SDL_LockAudioDevice( audioDevice );
	}
}

/*
===============
SNDDMA_Submit
===============
*/
void SNDDMA_Submit( void ) {
	if ( audioDevice != 0 ) {
		SDL_UnlockAudioDevice( audioDevice );
	}
}

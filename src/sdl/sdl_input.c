/*
===========================================================================
Return to Castle Wolfenstein single player GPL Source Code

SDL2 input implementation for the modern macOS (arm64) port. Replaces the
X11 keyboard/mouse code in unix/linux_glimp.c. Translates SDL events into
the engine's event queue via Sys_QueEvent().
===========================================================================
*/

#include <SDL.h>
#include "../game/q_shared.h"
#include "../qcommon/qcommon.h"
#include "../ui/keycodes.h"

extern void Sys_QueEvent( int time, sysEventType_t type, int value, int value2, int ptrLength, void *ptr );
extern SDL_Window *SDLimp_GetWindow( void );

static qboolean in_initialized = qfalse;
static qboolean mouseActive = qfalse;
static cvar_t *in_nograb;

/*
===============
IN_TranslateSDLToQ3Key
===============
*/
static int IN_TranslateSDLToQ3Key( SDL_Keysym *keysym ) {
	SDL_Keycode k = keysym->sym;

	// printable ASCII range maps straight through (lowercased letters)
	if ( k >= SDLK_SPACE && k < SDLK_DELETE ) {
		// a-z stay as-is; everything else in range is its ascii value
		return k;
	}

	switch ( k ) {
	case SDLK_TAB:          return K_TAB;
	case SDLK_RETURN:       return K_ENTER;
	case SDLK_ESCAPE:       return K_ESCAPE;
	case SDLK_BACKSPACE:    return K_BACKSPACE;
	case SDLK_DELETE:       return K_DEL;
	case SDLK_PAUSE:        return K_PAUSE;

	case SDLK_UP:           return K_UPARROW;
	case SDLK_DOWN:         return K_DOWNARROW;
	case SDLK_LEFT:         return K_LEFTARROW;
	case SDLK_RIGHT:        return K_RIGHTARROW;

	case SDLK_LALT:
	case SDLK_RALT:         return K_ALT;
	case SDLK_LCTRL:
	case SDLK_RCTRL:        return K_CTRL;
	case SDLK_LSHIFT:
	case SDLK_RSHIFT:       return K_SHIFT;
	case SDLK_LGUI:
	case SDLK_RGUI:         return K_COMMAND;
	case SDLK_CAPSLOCK:     return K_CAPSLOCK;

	case SDLK_INSERT:       return K_INS;
	case SDLK_PAGEUP:       return K_PGUP;
	case SDLK_PAGEDOWN:     return K_PGDN;
	case SDLK_HOME:         return K_HOME;
	case SDLK_END:          return K_END;

	case SDLK_F1:           return K_F1;
	case SDLK_F2:           return K_F2;
	case SDLK_F3:           return K_F3;
	case SDLK_F4:           return K_F4;
	case SDLK_F5:           return K_F5;
	case SDLK_F6:           return K_F6;
	case SDLK_F7:           return K_F7;
	case SDLK_F8:           return K_F8;
	case SDLK_F9:           return K_F9;
	case SDLK_F10:          return K_F10;
	case SDLK_F11:          return K_F11;
	case SDLK_F12:          return K_F12;
	case SDLK_F13:          return K_F13;
	case SDLK_F14:          return K_F14;
	case SDLK_F15:          return K_F15;

	case SDLK_KP_7:         return K_KP_HOME;
	case SDLK_KP_8:         return K_KP_UPARROW;
	case SDLK_KP_9:         return K_KP_PGUP;
	case SDLK_KP_4:         return K_KP_LEFTARROW;
	case SDLK_KP_5:         return K_KP_5;
	case SDLK_KP_6:         return K_KP_RIGHTARROW;
	case SDLK_KP_1:         return K_KP_END;
	case SDLK_KP_2:         return K_KP_DOWNARROW;
	case SDLK_KP_3:         return K_KP_PGDN;
	case SDLK_KP_0:         return K_KP_INS;
	case SDLK_KP_PERIOD:    return K_KP_DEL;
	case SDLK_KP_DIVIDE:    return K_KP_SLASH;
	case SDLK_KP_MINUS:     return K_KP_MINUS;
	case SDLK_KP_PLUS:      return K_KP_PLUS;
	case SDLK_NUMLOCKCLEAR: return K_KP_NUMLOCK;
	case SDLK_KP_MULTIPLY:  return K_KP_STAR;
	case SDLK_KP_EQUALS:    return K_KP_EQUALS;
	case SDLK_KP_ENTER:     return K_KP_ENTER;

	default:
		break;
	}

	// unknown printable (e.g. keypad over 127) - fall back to low 8 bits
	if ( k >= 0 && k < 256 ) {
		return k;
	}
	return 0;
}

/*
===============
IN_ActivateMouse / IN_DeactivateMouse
===============
*/
static void IN_ActivateMouse( void ) {
	if ( mouseActive || ( in_nograb && in_nograb->integer ) ) {
		return;
	}
	SDL_SetRelativeMouseMode( SDL_TRUE );
	mouseActive = qtrue;
}

static void IN_DeactivateMouse( void ) {
	if ( !mouseActive ) {
		return;
	}
	SDL_SetRelativeMouseMode( SDL_FALSE );
	mouseActive = qfalse;
}

/*
===============
Sys_SendKeyEvents

Pump the SDL event queue, converting to engine events. Called from
Sys_GetEvent() once per frame.
===============
*/
void Sys_SendKeyEvents( void ) {
	SDL_Event e;
	int key;

	if ( !in_initialized ) {
		return;
	}

	while ( SDL_PollEvent( &e ) ) {
		switch ( e.type ) {
		case SDL_KEYDOWN:
			key = IN_TranslateSDLToQ3Key( &e.key.keysym );
			if ( key ) {
				Sys_QueEvent( 0, SE_KEY, key, qtrue, 0, NULL );
			}
			break;
		case SDL_KEYUP:
			key = IN_TranslateSDLToQ3Key( &e.key.keysym );
			if ( key ) {
				Sys_QueEvent( 0, SE_KEY, key, qfalse, 0, NULL );
			}
			break;

		case SDL_TEXTINPUT: {
			const char *c = e.text.text;
			while ( *c ) {
				// only queue 7-bit ascii; the engine console is ascii
				if ( (unsigned char)*c < 128 ) {
					Sys_QueEvent( 0, SE_CHAR, *c, 0, 0, NULL );
				}
				c++;
			}
			break;
		}

		case SDL_MOUSEBUTTONDOWN:
		case SDL_MOUSEBUTTONUP: {
			int qkey = 0;
			qboolean down = ( e.type == SDL_MOUSEBUTTONDOWN ) ? qtrue : qfalse;
			switch ( e.button.button ) {
			case SDL_BUTTON_LEFT:   qkey = K_MOUSE1; break;
			case SDL_BUTTON_RIGHT:  qkey = K_MOUSE2; break;
			case SDL_BUTTON_MIDDLE: qkey = K_MOUSE3; break;
			case SDL_BUTTON_X1:     qkey = K_MOUSE4; break;
			case SDL_BUTTON_X2:     qkey = K_MOUSE5; break;
			default: break;
			}
			if ( qkey ) {
				Sys_QueEvent( 0, SE_KEY, qkey, down, 0, NULL );
			}
			break;
		}

		case SDL_MOUSEWHEEL:
			if ( e.wheel.y > 0 ) {
				Sys_QueEvent( 0, SE_KEY, K_MWHEELUP, qtrue, 0, NULL );
				Sys_QueEvent( 0, SE_KEY, K_MWHEELUP, qfalse, 0, NULL );
			} else if ( e.wheel.y < 0 ) {
				Sys_QueEvent( 0, SE_KEY, K_MWHEELDOWN, qtrue, 0, NULL );
				Sys_QueEvent( 0, SE_KEY, K_MWHEELDOWN, qfalse, 0, NULL );
			}
			break;

		case SDL_MOUSEMOTION:
			if ( mouseActive && ( e.motion.xrel || e.motion.yrel ) ) {
				Sys_QueEvent( 0, SE_MOUSE, e.motion.xrel, e.motion.yrel, 0, NULL );
			}
			break;

		case SDL_WINDOWEVENT:
			switch ( e.window.event ) {
			case SDL_WINDOWEVENT_FOCUS_GAINED:
				IN_ActivateMouse();
				break;
			case SDL_WINDOWEVENT_FOCUS_LOST:
				IN_DeactivateMouse();
				break;
			default:
				break;
			}
			break;

		case SDL_QUIT:
			Com_Quit_f();
			break;

		default:
			break;
		}
	}
}

/*
===============
IN_Frame
===============
*/
void IN_Frame( void ) {
	// mouse activation is handled on focus events; nothing else to flush
	// since motion events are queued immediately in Sys_SendKeyEvents.
}

/*
===============
IN_Activate
===============
*/
void IN_Activate( void ) {
	IN_ActivateMouse();
}

/*
===============
IN_Init
===============
*/
void IN_Init( void ) {
	if ( SDL_WasInit( SDL_INIT_VIDEO ) == 0 ) {
		SDL_InitSubSystem( SDL_INIT_VIDEO );
	}

	in_nograb = Cvar_Get( "in_nograb", "0", CVAR_ARCHIVE );

	SDL_StartTextInput();
	in_initialized = qtrue;

	IN_ActivateMouse();

	Com_Printf( "------- Input Initialization (SDL2) -------\n" );
}

/*
===============
IN_Shutdown
===============
*/
void IN_Shutdown( void ) {
	IN_DeactivateMouse();
	SDL_StopTextInput();
	in_initialized = qfalse;
}

/*
===============
Joystick stubs (not implemented on the SDL backend yet)
===============
*/
void IN_StartupJoystick( void ) {
}

void IN_JoyMove( void ) {
}

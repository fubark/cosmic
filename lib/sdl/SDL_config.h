// This is based on SDL/include/SDL_config.h
// In addition to using SDL_config_minimal.h, we add platform specific defines.
// This is to avoid relying on configure or CMake to generate the configuration.

#ifndef SDL_config_h_
#define SDL_config_h_

#include "SDL_platform.h"

// Use GLES2 and EGL headers that come with SDL.
#define SDL_USE_BUILTIN_OPENGL_DEFINITIONS 1

/* Add any platform that doesn't build using the configure system. */
#if defined(__WIN32__)
#include "SDL_config_windows.h"
#elif defined(__WINRT__)
#include "SDL_config_winrt.h"
#elif defined(__MACOSX__)
#include "SDL_config_macosx.h"
// Custom defines.
#define SDL_JOYSTICK_DISABLED 1
#undef SDL_JOYSTICK_MFI
// End custom defines.
#elif defined(__IPHONEOS__)
#include "SDL_config_iphoneos.h"
#elif defined(__ANDROID__)
#include "SDL_config_android.h"
#elif defined(__PSP__)
#include "SDL_config_psp.h"
#elif defined(__OS2__)
#include "SDL_config_os2.h"
#elif defined(__EMSCRIPTEN__)
#include "SDL_config_emscripten.h"
#else
/* This is a minimal configuration just to get SDL running on new platforms. */
#include "SDL_config_minimal.h"

#define HAVE_LIBC 1
#if HAVE_LIBC
// Useful headers
#define STDC_HEADERS 1
#define HAVE_ALLOCA_H 1
#define HAVE_CTYPE_H 1
#define HAVE_FLOAT_H 1
#define HAVE_ICONV_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MALLOC_H 1
#define HAVE_MATH_H 1
#define HAVE_MEMORY_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_WCHAR_H 1

// C library functions
#define HAVE_DLOPEN 1
#define HAVE_MALLOC 1
#define HAVE_CALLOC 1
#define HAVE_REALLOC 1
#define HAVE_FREE 1
#define HAVE_ALLOCA 1
#ifndef __WIN32__ /* Don't use C runtime versions of these on Windows */
#define HAVE_GETENV 1
#define HAVE_SETENV 1
#define HAVE_PUTENV 1
#define HAVE_UNSETENV 1
#endif
#define HAVE_QSORT 1
#define HAVE_ABS 1
#define HAVE_BCOPY 1
#define HAVE_MEMSET 1
#define HAVE_MEMCPY 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMCMP 1
#define HAVE_WCSLEN 1
#define HAVE_WCSDUP 1
#define HAVE_WCSSTR 1
#define HAVE_WCSCMP 1
#define HAVE_WCSNCMP 1
#define HAVE_WCSCASECMP 1
#define HAVE_WCSNCASECMP 1
#define HAVE_STRLEN 1
#define HAVE_INDEX 1
#define HAVE_RINDEX 1
#define HAVE_STRCHR 1
#define HAVE_STRRCHR 1
#define HAVE_STRSTR 1
#define HAVE_STRTOK_R 1
#define HAVE_STRTOL 1
#define HAVE_STRTOUL 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1
#define HAVE_STRTOD 1
#define HAVE_ATOI 1
#define HAVE_ATOF 1
#define HAVE_STRCMP 1
#define HAVE_STRNCMP 1
#define HAVE_STRCASECMP 1
#define HAVE_STRNCASECMP 1
#define HAVE_SSCANF 1
#define HAVE_VSSCANF 1
#define HAVE_VSNPRINTF 1
#define HAVE_M_PI 1
#define HAVE_ACOS 1
#define HAVE_ACOSF 1
#define HAVE_ASIN 1
#define HAVE_ASINF 1
#define HAVE_ATAN 1
#define HAVE_ATANF 1
#define HAVE_ATAN2 1
#define HAVE_ATAN2F 1
#define HAVE_CEIL 1
#define HAVE_CEILF 1
#define HAVE_COPYSIGN 1
#define HAVE_COPYSIGNF 1
#define HAVE_COS 1
#define HAVE_COSF 1
#define HAVE_EXP 1
#define HAVE_EXPF 1
#define HAVE_FABS 1
#define HAVE_FABSF 1
#define HAVE_FLOOR 1
#define HAVE_FLOORF 1
#define HAVE_FMOD 1
#define HAVE_FMODF 1
#define HAVE_LOG 1
#define HAVE_LOGF 1
#define HAVE_LOG10 1
#define HAVE_LOG10F 1
#define HAVE_LROUND 1
#define HAVE_LROUNDF 1
#define HAVE_POW 1
#define HAVE_POWF 1
#define HAVE_ROUND 1
#define HAVE_ROUNDF 1
#define HAVE_SCALBN 1
#define HAVE_SCALBNF 1
#define HAVE_SIN 1
#define HAVE_SINF 1
#define HAVE_SQRT 1
#define HAVE_SQRTF 1
#define HAVE_TAN 1
#define HAVE_TANF 1
#define HAVE_TRUNC 1
#define HAVE_TRUNCF 1
#define HAVE_FSEEKO 1
#define HAVE_SIGACTION 1
#define HAVE_SA_SIGACTION 1
#define HAVE_SETJMP 1
#define HAVE_NANOSLEEP 1
#define HAVE_SYSCONF 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_MPROTECT 1
#define HAVE_ICONV 1
#define HAVE_PTHREAD_SETNAME_NP 1
#define HAVE_SEM_TIMEDWAIT 1
#define HAVE_GETAUXVAL 1
#define HAVE_POLL 1
#define HAVE__EXIT 1

#elif defined(__WIN32__)
#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_FLOAT_H 1
#else
/* We may need some replacement for stdarg.h here */
#include <stdarg.h>
#endif /* HAVE_LIBC */

#define SDL_VIDEO_OPENGL 1
//#define SDL_VIDEO_OPENGL_ES 1
//#define SDL_VIDEO_OPENGL_ES2 1
//#define SDL_VIDEO_OPENGL_EGL 1

#define SDL_VIDEO_RENDER_OGL 1
//#define SDL_VIDEO_RENDER_OGL_ES 1
//#define SDL_VIDEO_RENDER_OGL_ES2 1

//#define SDL_VIDEO_VULKAN 1

#ifdef __LINUX__
    #define SDL_TIMER_UNIX 1
    #define SDL_LOADSO_DLOPEN 1
    #define SDL_FILESYSTEM_UNIX 1
    #define SDL_POWER_LINUX 1
    #define SDL_THREAD_PTHREAD 1
    #define SDL_THREAD_PTHREAD_RECURSIVE_MUTEX 1

    // Provides the interface between opengl and x11.
    #define SDL_VIDEO_OPENGL_GLX 1

    #define SDL_VIDEO_DRIVER_DUMMY 1
    #define SDL_VIDEO_DRIVER_X11 1
    #define SDL_VIDEO_DRIVER_X11_HAS_XKBKEYCODETOKEYSYM 1
    #define SDL_VIDEO_DRIVER_X11_SUPPORTS_GENERIC_EVENTS 1
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC "libX11.so.6"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XEXT "libXext.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XCURSOR "libXcursor.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XINERAMA "libXinerama.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XINPUT2 "libXi.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XFIXES "libXfixes.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XRANDR "libXrandr.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XSS "libXss.so"
    #define SDL_VIDEO_DRIVER_X11_DYNAMIC_XVIDMODE "libXxf86vm.so"
    #define SDL_VIDEO_DRIVER_X11_XCURSOR 1
    #define SDL_VIDEO_DRIVER_X11_XDBE 1
    #define SDL_VIDEO_DRIVER_X11_XINERAMA 1
    #define SDL_VIDEO_DRIVER_X11_XINPUT2 1
    #define SDL_VIDEO_DRIVER_X11_XINPUT2_SUPPORTS_MULTITOUCH 1
    #define SDL_VIDEO_DRIVER_X11_XFIXES 1
    #define SDL_VIDEO_DRIVER_X11_XRANDR 1
    #define SDL_VIDEO_DRIVER_X11_XSCRNSAVER 1
    #define SDL_VIDEO_DRIVER_X11_XSHAPE 1
    #define SDL_VIDEO_DRIVER_X11_XVIDMODE 1

    #define SDL_ASSEMBLY_ROUTINES 1
#endif

#endif /* platform config */

#ifdef USING_GENERATED_CONFIG_H
#error Wrong SDL_config.h, check your include path?
#endif

#endif /* SDL_config_h_ */

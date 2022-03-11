// zig addCSourceFile doesn't work well with .h files, so we create a c file and include the header.
// STB_TRUETYPE_IMPLEMENTATION is defined in build.zig cflags.

// Latest rasterizer.
#define STBTT_RASTERIZER_VERSION 2

#include "stb_truetype.h"
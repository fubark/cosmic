
#ifndef FTOPTION_H_
#include "../../../vendor/include/freetype/config/ftoption.h"

// Disable zlib support for now.
#undef FT_CONFIG_OPTION_USE_ZLIB
// Disable bitmap font format.
#undef TT_CONFIG_OPTION_BDF
// Disable svg.
#undef FT_CONFIG_OPTION_SVG
#endif 


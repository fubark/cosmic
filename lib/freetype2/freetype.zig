const c = @cImport({
    @cInclude("freetype/freetype.h");
});

pub usingnamespace c;

pub const Face = c.FT_FaceRec_;
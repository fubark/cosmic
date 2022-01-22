const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

// Based on w3c specs.
// https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/keyCode
pub const KeyCode = enum(u8) {
    Unknown = 0,
    Backspace = 8,
    Tab = 9,
    Enter = 13,
    Shift = 16,
    Control = 17,
    Alt = 18,
    Pause = 19,
    CapsLock = 20,
    Escape = 27,
    Space = 32,
    PageUp = 33,
    PageDown = 34,
    End = 35,
    Home = 36,
    ArrowUp = 37,
    ArrowLeft = 38,
    ArrowRight = 39,
    ArrowDown = 40,
    PrintScreen = 44,
    Insert = 45,
    Delete = 46,

    Digit0 = 48,
    Digit1 = 49,
    Digit2 = 50,
    Digit3 = 51,
    Digit4 = 52,
    Digit5 = 53,
    Digit6 = 54,
    Digit7 = 55,
    Digit8 = 56,
    Digit9 = 57,

    A = 65,
    B = 66,
    C = 67,
    D = 68,
    E = 69,
    F = 70,
    G = 71,
    H = 72,
    I = 73,
    J = 74,
    K = 75,
    L = 76,
    M = 77,
    N = 78,
    O = 79,
    P = 80,
    Q = 81,
    R = 82,
    S = 83,
    T = 84,
    U = 85,
    V = 86,
    W = 87,
    X = 88,
    Y = 89,
    Z = 90,

    ContextMenu = 93,

    F1 = 112,
    F2 = 113,
    F3 = 114,
    F4 = 115,
    F5 = 116,
    F6 = 117,
    F7 = 118,
    F8 = 119,
    F9 = 120,
    F10 = 121,
    F11 = 122,
    F12 = 123,
    F13 = 124,
    F14 = 125,
    F15 = 126,
    F16 = 127,
    F17 = 128,
    F18 = 129,
    F19 = 130,
    F20 = 131,
    F21 = 132,
    F22 = 133,
    F23 = 134,
    F24 = 135,

    ScrollLock = 145,
    Semicolon = 186,
    Equal = 187,
    Comma = 188,
    Minus = 189,
    Period = 190,
    Slash = 191,
    Backquote = 192,
    BracketLeft = 219,
    Backslash = 220,
    BracketRight = 221,
    Quote = 222,
};

const ShiftMask = 8;
const ControlMask = 4;
const AltMask = 2;
const MetaMask = 1;

const MaxCodes = 223;
const KeyCharMap = b: {
    var map: [MaxCodes][2]u8 = undefined;
    const S = struct {
        map: *[MaxCodes][2]u8,
        fn set(self: *@This(), code: KeyCode, shift: bool, char: u8) void {
            self.map[@enumToInt(code)][@boolToInt(shift)] = char;
        }
    };

    // Default to 0.
    var s = S{ .map = &map };
    for (std.enums.values(KeyCode)) |code| {
        s.set(code, false, 0);
        s.set(code, true, 0);
    }
    s.set(.Digit1, true, '!');
    s.set(.Digit2, true, '@');
    s.set(.Digit3, true, '#');
    s.set(.Digit4, true, '$');
    s.set(.Digit5, true, '%');
    s.set(.Digit6, true, '^');
    s.set(.Digit7, true, '&');
    s.set(.Digit8, true, '*');
    s.set(.Digit9, true, '(');
    s.set(.Digit0, true, ')');
    s.set(.Period, false, '.');
    s.set(.Period, true, '>');
    s.set(.Comma, false, ',');
    s.set(.Comma, true, '<');
    s.set(.Slash, false, '/');
    s.set(.Slash, true, '?');
    s.set(.Semicolon, false, ';');
    s.set(.Semicolon, true, ':');
    s.set(.Quote, false, '\'');
    s.set(.Quote, true, '"');
    s.set(.BracketLeft, false, '[');
    s.set(.BracketLeft, true, '{');
    s.set(.BracketRight, false, ']');
    s.set(.BracketRight, true, '}');
    s.set(.Backslash, false, '\\');
    s.set(.Backslash, true, '|');
    s.set(.Backquote, false, '`');
    s.set(.Backquote, true, '~');
    s.set(.Minus, false, '-');
    s.set(.Minus, true, '_');
    s.set(.Equal, false, '=');
    s.set(.Equal, true, '+');
    s.set(.Space, false, ' ');
    s.set(.Space, true, ' ');

    var i: u16 = @enumToInt(KeyCode.A);
    while (i <= @enumToInt(KeyCode.Z)) : (i += 1) {
        map[i][0] = std.ascii.toLower(i);
        map[i][1] = i;
    }

    i = @enumToInt(KeyCode.Digit0);
    while (i <= @enumToInt(KeyCode.Digit9)) : (i += 1) {
        map[i][0] = i;
    }

    break :b map;
};

pub const KeyDownEvent = struct {
    const Self = @This();

    code: KeyCode,

    // Keyboard modifiers.
    mods: u8,

    // Whether it's a repeated key down, pressed and held. Frequency depends on target platform settings.
    is_repeat: bool,

    pub fn init(code: KeyCode, is_repeat: bool, shift_pressed: bool, control_pressed: bool, alt_pressed: bool, meta_pressed: bool) Self {
        var mods: u8 = 0;
        if (shift_pressed) {
            mods |= ShiftMask;
        }
        if (control_pressed) {
            mods |= ControlMask;
        }
        if (alt_pressed) {
            mods |= AltMask;
        }
        if (meta_pressed) {
            mods |= MetaMask;
        }
        return .{
            .code = code,
            .mods = mods,
            .is_repeat = is_repeat,
        };
    }

    // Returns the ascii char. Returns 0 if it's not a visible char.
    pub fn getKeyChar(self: Self) u8 {
        const shift_idx = @boolToInt((self.mods & ShiftMask) == ShiftMask);
        return KeyCharMap[@enumToInt(self.code)][shift_idx];
    }

    pub fn isShiftPressed(self: Self) bool {
        return self.mods & ShiftMask > 0;
    }

    pub fn isControlPressed(self: Self) bool {
        return self.mods & ControlMask > 0;
    }

    pub fn isAltPressed(self: Self) bool {
        return self.mods & AltMask > 0;
    }

    pub fn isMetaPressed(self: Self) bool {
        return self.mods & MetaMask > 0;
    }
};

pub const KeyUpEvent = struct {
    const Self = @This();

    code: KeyCode,

    // Keyboard modifiers.
    mods: u8,

    pub fn initWithMods(code: KeyCode, mods: u8) @This() {
        return .{
            .code = code,
            .mods = mods,
        };
    }

    pub fn init(code: KeyCode, shift_pressed: bool, control_pressed: bool, alt_pressed: bool, meta_pressed: bool) Self {
        var mods: u8 = 0;
        if (shift_pressed) {
            mods |= ShiftMask;
        }
        if (control_pressed) {
            mods |= ControlMask;
        }
        if (alt_pressed) {
            mods |= AltMask;
        }
        if (meta_pressed) {
            mods |= MetaMask;
        }
        return .{
            .code = code,
            .mods = mods,
        };
    }

    // Returns the ascii char. Returns 0 if it's not a visible char.
    pub fn getKeyChar(self: Self) u8 {
        const shift_idx = @boolToInt((self.mods & ShiftMask) == ShiftMask);
        return KeyCharMap[@enumToInt(self.code)][shift_idx];
    }

    pub fn isShiftPressed(self: Self) bool {
        return self.mods & ShiftMask > 0;
    }

    pub fn isControlPressed(self: Self) bool {
        return self.mods & ControlMask > 0;
    }

    pub fn isAltPressed(self: Self) bool {
        return self.mods & AltMask > 0;
    }

    pub fn isMetaPressed(self: Self) bool {
        return self.mods & MetaMask > 0;
    }
};

test "KeyUpEvent.getKeyChar" {
    const S = struct {
        fn case(code: KeyCode, shift: bool, expected: u8) !void {
            const mods: u8 = if (shift) ShiftMask else 0;
            try t.eq(KeyUpEvent.initWithMods(code, mods).getKeyChar(), expected);
        }
    };
    const case = S.case;

    try case(.A, false, 'a');
    try case(.A, true, 'A');
    try case(.Z, false, 'z');
    try case(.Z, true, 'Z');
    try case(.Digit1, false, '1');
    try case(.Digit1, true, '!');
    try case(.Digit2, false, '2');
    try case(.Digit2, true, '@');
    try case(.Digit3, false, '3');
    try case(.Digit3, true, '#');
    try case(.Digit4, false, '4');
    try case(.Digit4, true, '$');
    try case(.Digit5, false, '5');
    try case(.Digit5, true, '%');
    try case(.Digit6, false, '6');
    try case(.Digit6, true, '^');
    try case(.Digit7, false, '7');
    try case(.Digit7, true, '&');
    try case(.Digit8, false, '8');
    try case(.Digit8, true, '*');
    try case(.Digit9, false, '9');
    try case(.Digit9, true, '(');
    try case(.Digit0, false, '0');
    try case(.Digit0, true, ')');
    try case(.Period, false, '.');
    try case(.Period, true, '>');
    try case(.Comma, false, ',');
    try case(.Comma, true, '<');
    try case(.Slash, false, '/');
    try case(.Slash, true, '?');
    try case(.Semicolon, false, ';');
    try case(.Semicolon, true, ':');
    try case(.Quote, false, '\'');
    try case(.Quote, true, '"');
    try case(.BracketLeft, false, '[');
    try case(.BracketLeft, true, '{');
    try case(.BracketRight, false, ']');
    try case(.BracketRight, true, '}');
    try case(.Backslash, false, '\\');
    try case(.Backslash, true, '|');
    try case(.Backquote, false, '`');
    try case(.Backquote, true, '~');
    try case(.Minus, false, '-');
    try case(.Minus, true, '_');
    try case(.Equal, false, '=');
    try case(.Equal, true, '+');
    try case(.Space, false, ' ');
    try case(.Space, true, ' ');
}
const sdl = @import("sdl");
const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const platform = @import("platform.zig");
const KeyDownEvent = platform.KeyDownEvent;
const KeyUpEvent = platform.KeyUpEvent;
const KeyCode = platform.KeyCode;
const MouseDownEvent = platform.MouseDownEvent;
const MouseUpEvent = platform.MouseUpEvent;
const MouseButton = platform.MouseButton;
const MouseMoveEvent = platform.MouseMoveEvent;
const log = stdx.log.scoped(.input_sdl);

// Converts sdl events into canonical events.

const ButtonMap = b: {
    var arr: [6]MouseButton = undefined;
    arr[sdl.SDL_BUTTON_LEFT] = .left;
    arr[sdl.SDL_BUTTON_RIGHT] = .right;
    arr[sdl.SDL_BUTTON_MIDDLE] = .middle;
    arr[sdl.SDL_BUTTON_X1] = .x1;
    arr[sdl.SDL_BUTTON_X2] = .x2;
    break :b arr;
};

test "ButtonMap" {
    try t.eq(ButtonMap[sdl.SDL_BUTTON_LEFT], .left);
    try t.eq(ButtonMap[sdl.SDL_BUTTON_RIGHT], .right);
    try t.eq(ButtonMap[sdl.SDL_BUTTON_MIDDLE], .middle);
    try t.eq(ButtonMap[sdl.SDL_BUTTON_X1], .x1);
    try t.eq(ButtonMap[sdl.SDL_BUTTON_X2], .x2);
}

pub fn initMouseDownEvent(event: sdl.SDL_MouseButtonEvent) MouseDownEvent {
    return MouseDownEvent.init(
        ButtonMap[event.button],
        @intCast(i16, event.x),
        @intCast(i16, event.y),
        event.clicks,
    );
}

pub fn initMouseUpEvent(event: sdl.SDL_MouseButtonEvent) MouseUpEvent {
    return MouseUpEvent.init(
        ButtonMap[event.button],
        @intCast(i16, event.x),
        @intCast(i16, event.y),
        event.clicks,
    );
}

pub fn initMouseMoveEvent(event: sdl.SDL_MouseMotionEvent) MouseMoveEvent {
    return MouseMoveEvent.init(@intCast(i16, event.x), @intCast(i16, event.y));
}

pub fn initMouseScrollEvent(cur_x: i16, cur_y: i16, event: sdl.SDL_MouseWheelEvent) platform.MouseScrollEvent {
    return platform.MouseScrollEvent.init(
        cur_x,
        cur_y,
        -event.preciseY * 20,
    );
}

pub fn initKeyDownEvent(e: sdl.SDL_KeyboardEvent) KeyDownEvent {
    const code = toCanonicalKeyCode(e.keysym.sym);

    const shift = e.keysym.mod & (sdl.KMOD_LSHIFT | sdl.KMOD_RSHIFT);
    const ctrl = e.keysym.mod & (sdl.KMOD_LCTRL | sdl.KMOD_RCTRL);
    const alt = e.keysym.mod & (sdl.KMOD_LALT | sdl.KMOD_RALT);
    const meta = e.keysym.mod & (sdl.KMOD_LGUI | sdl.KMOD_RGUI);

    return KeyDownEvent.init(code, e.repeat == 1, shift > 0, ctrl > 0, alt > 0, meta > 0);
}

pub fn initKeyUpEvent(e: sdl.SDL_KeyboardEvent) KeyUpEvent {
    const code = toCanonicalKeyCode(e.keysym.sym);

    const shift = e.keysym.mod & (sdl.KMOD_LSHIFT | sdl.KMOD_RSHIFT);
    const ctrl = e.keysym.mod & (sdl.KMOD_LCTRL | sdl.KMOD_RCTRL);
    const alt = e.keysym.mod & (sdl.KMOD_LALT | sdl.KMOD_RALT);
    const meta = e.keysym.mod & (sdl.KMOD_LGUI | sdl.KMOD_RGUI);

    return KeyUpEvent.init(code, shift > 0, ctrl > 0, alt > 0, meta > 0);
}

const MaxLowerRangeCodes = 123;
const LowerRangeMap = b: {
    var map: [MaxLowerRangeCodes]KeyCode = undefined;

    for (map) |*it| {
        it.* = .Unknown;
    }
    map[sdl.SDLK_UNKNOWN] = .Unknown;
    map[sdl.SDLK_RETURN] = .Enter;
    map[sdl.SDLK_ESCAPE] = .Escape;
    map[sdl.SDLK_BACKSPACE] = .Backspace;
    map[sdl.SDLK_TAB] = .Tab;
    map[sdl.SDLK_SPACE] = .Space;
    map[sdl.SDLK_COMMA] = .Comma;
    map[sdl.SDLK_MINUS] = .Minus;
    map[sdl.SDLK_PERIOD] = .Period;
    map[sdl.SDLK_SLASH] = .Slash;
    map[sdl.SDLK_SEMICOLON] = .Semicolon;
    map[sdl.SDLK_EQUALS] = .Equal;
    map[sdl.SDLK_LEFTBRACKET] = .BracketLeft;
    map[sdl.SDLK_BACKSLASH] = .Backslash;
    map[sdl.SDLK_RIGHTBRACKET] = .BracketRight;
    map[sdl.SDLK_BACKQUOTE] = .Backquote;
    for (map[sdl.SDLK_0 .. sdl.SDLK_9 + 1]) |*it, i| {
        it.* = @intToEnum(KeyCode, @enumToInt(KeyCode.Digit0) + i);
    }
    for (map[sdl.SDLK_a .. sdl.SDLK_z + 1]) |*it, i| {
        it.* = @intToEnum(KeyCode, @enumToInt(KeyCode.A) + i);
    }

    break :b map;
};

const UpperRangeMap = b: {
    var map: [256]KeyCode = undefined;

    const S = struct {
        fn toUpperOffset(code: sdl.SDL_Keycode) u8 {
            const ucode = @bitCast(u32, code);
            return @intCast(u8, ucode & ~(@as(u32, 1) << 30));
        }
    };

    for (map) |*it| {
        it.* = .Unknown;
    }
    const offset = S.toUpperOffset;

    for (map[offset(sdl.SDLK_F1) .. offset(sdl.SDLK_F12) + 1]) |*it, i| {
        it.* = @intToEnum(KeyCode, @enumToInt(KeyCode.F1) + i);
    }
    map[offset(sdl.SDLK_CAPSLOCK)] = .CapsLock;
    map[offset(sdl.SDLK_PRINTSCREEN)] = .PrintScreen;
    map[offset(sdl.SDLK_SCROLLLOCK)] = .ScrollLock;
    map[offset(sdl.SDLK_PAUSE)] = .Pause;
    map[offset(sdl.SDLK_INSERT)] = .Insert;
    map[offset(sdl.SDLK_HOME)] = .Home;
    map[offset(sdl.SDLK_PAGEUP)] = .PageUp;
    map[offset(sdl.SDLK_DELETE)] = .Delete;
    map[offset(sdl.SDLK_END)] = .End;
    map[offset(sdl.SDLK_PAGEDOWN)] = .PageDown;
    map[offset(sdl.SDLK_RIGHT)] = .ArrowRight;
    map[offset(sdl.SDLK_LEFT)] = .ArrowLeft;
    map[offset(sdl.SDLK_DOWN)] = .ArrowDown;
    map[offset(sdl.SDLK_UP)] = .ArrowUp;
    map[offset(sdl.SDLK_LGUI)] = .Meta;
    map[offset(sdl.SDLK_LCTRL)] = .ControlLeft;
    map[offset(sdl.SDLK_RCTRL)] = .ControlRight;
    map[offset(sdl.SDLK_APPLICATION)] = .ContextMenu;
    map[offset(sdl.SDLK_LALT)] = .AltLeft;
    map[offset(sdl.SDLK_RALT)] = .AltRight;

    break :b map;
};

fn toCanonicalKeyCode(code: sdl.SDL_Keycode) KeyCode {
    const ucode = @bitCast(u32, code);
    if (code < MaxLowerRangeCodes) {
        return LowerRangeMap[ucode];
    } else if (code <= 1073742055) {
        // Remove most significant bit.
        const offset = ucode & ~(@as(u32, 1) << 30);
        return UpperRangeMap[offset];
    } else {
        return .Unknown;
    }
}

test "toCanonicalKeyCode" {
    const S = struct {
        fn case(code: sdl.SDL_Keycode, exp: KeyCode) !void {
            try t.eq(toCanonicalKeyCode(code), exp);
        }
    };
    const case = S.case;

    try case(sdl.SDLK_UNKNOWN, .Unknown);
    try case(sdl.SDLK_RETURN, .Enter);
    try case(sdl.SDLK_ESCAPE, .Escape);
    try case(sdl.SDLK_BACKSPACE, .Backspace);
    try case(sdl.SDLK_TAB, .Tab);
    try case(sdl.SDLK_SPACE, .Space);

    // Not sure why these are in SDL since the same keycode is returned for both shift mod and without.
    // pub const SDLK_EXCLAIM: c_int = 33;
    // pub const SDLK_QUOTEDBL: c_int = 34;
    // pub const SDLK_HASH: c_int = 35;
    // pub const SDLK_PERCENT: c_int = 37;
    // pub const SDLK_DOLLAR: c_int = 36;
    // pub const SDLK_AMPERSAND: c_int = 38;
    // pub const SDLK_QUOTE: c_int = 39;
    // pub const SDLK_LEFTPAREN: c_int = 40;
    // pub const SDLK_RIGHTPAREN: c_int = 41;
    // pub const SDLK_ASTERISK: c_int = 42;
    // pub const SDLK_PLUS: c_int = 43;

    try case(sdl.SDLK_COMMA, .Comma);
    try case(sdl.SDLK_MINUS, .Minus);
    try case(sdl.SDLK_PERIOD, .Period);
    try case(sdl.SDLK_SLASH, .Slash);
    try case(sdl.SDLK_0, .Digit0);
    try case(sdl.SDLK_1, .Digit1);
    try case(sdl.SDLK_2, .Digit2);
    try case(sdl.SDLK_3, .Digit3);
    try case(sdl.SDLK_4, .Digit4);
    try case(sdl.SDLK_5, .Digit5);
    try case(sdl.SDLK_6, .Digit6);
    try case(sdl.SDLK_7, .Digit7);
    try case(sdl.SDLK_8, .Digit8);
    try case(sdl.SDLK_9, .Digit9);

    //     pub const SDLK_COLON: c_int = 58;

    try case(sdl.SDLK_SEMICOLON, .Semicolon);

    // pub const SDLK_LESS: c_int = 60;

    try case(sdl.SDLK_EQUALS, .Equal);

    // pub const SDLK_GREATER: c_int = 62;
    // pub const SDLK_QUESTION: c_int = 63;
    // pub const SDLK_AT: c_int = 64;

    try case(sdl.SDLK_LEFTBRACKET, .BracketLeft);
    try case(sdl.SDLK_BACKSLASH, .Backslash);
    try case(sdl.SDLK_RIGHTBRACKET, .BracketRight);

    // pub const SDLK_CARET: c_int = 94;
    // pub const SDLK_UNDERSCORE: c_int = 95;

    try case(sdl.SDLK_BACKQUOTE, .Backquote);
    try case(sdl.SDLK_a, .A);
    try case(sdl.SDLK_b, .B);
    try case(sdl.SDLK_c, .C);
    try case(sdl.SDLK_d, .D);
    try case(sdl.SDLK_e, .E);
    try case(sdl.SDLK_f, .F);
    try case(sdl.SDLK_g, .G);
    try case(sdl.SDLK_h, .H);
    try case(sdl.SDLK_i, .I);
    try case(sdl.SDLK_j, .J);
    try case(sdl.SDLK_k, .K);
    try case(sdl.SDLK_l, .L);
    try case(sdl.SDLK_m, .M);
    try case(sdl.SDLK_n, .N);
    try case(sdl.SDLK_o, .O);
    try case(sdl.SDLK_p, .P);
    try case(sdl.SDLK_q, .Q);
    try case(sdl.SDLK_r, .R);
    try case(sdl.SDLK_s, .S);
    try case(sdl.SDLK_t, .T);
    try case(sdl.SDLK_u, .U);
    try case(sdl.SDLK_v, .V);
    try case(sdl.SDLK_w, .W);
    try case(sdl.SDLK_x, .X);
    try case(sdl.SDLK_y, .Y);
    try case(sdl.SDLK_z, .Z);

    try case(sdl.SDLK_CAPSLOCK, .CapsLock);
    try case(sdl.SDLK_F1, .F1);
    try case(sdl.SDLK_F2, .F2);
    try case(sdl.SDLK_F3, .F3);
    try case(sdl.SDLK_F4, .F4);
    try case(sdl.SDLK_F5, .F5);
    try case(sdl.SDLK_F6, .F6);
    try case(sdl.SDLK_F7, .F7);
    try case(sdl.SDLK_F8, .F8);
    try case(sdl.SDLK_F9, .F9);
    try case(sdl.SDLK_F10, .F10);
    try case(sdl.SDLK_F11, .F11);
    try case(sdl.SDLK_F12, .F12);
    try case(sdl.SDLK_PRINTSCREEN, .PrintScreen);
    try case(sdl.SDLK_SCROLLLOCK, .ScrollLock);
    try case(sdl.SDLK_PAUSE, .Pause);
    try case(sdl.SDLK_INSERT, .Insert);
    try case(sdl.SDLK_HOME, .Home);
    try case(sdl.SDLK_PAGEUP, .PageUp);
    try case(sdl.SDLK_DELETE, .Delete);
    try case(sdl.SDLK_END, .End);
    try case(sdl.SDLK_PAGEDOWN, .PageDown);
    try case(sdl.SDLK_RIGHT, .ArrowRight);
    try case(sdl.SDLK_LEFT, .ArrowLeft);
    try case(sdl.SDLK_DOWN, .ArrowDown);
    try case(sdl.SDLK_UP, .ArrowUp);
    try case(sdl.SDLK_LGUI, .Meta);
    try case(sdl.SDLK_LCTRL, .ControlLeft);
    try case(sdl.SDLK_RCTRL, .ControlRight);
    try case(sdl.SDLK_LALT, .AltLeft);
    try case(sdl.SDLK_RALT, .AltRight);

    // pub const SDLK_NUMLOCKCLEAR: c_int = 1073741907;
    // pub const SDLK_KP_DIVIDE: c_int = 1073741908;
    // pub const SDLK_KP_MULTIPLY: c_int = 1073741909;
    // pub const SDLK_KP_MINUS: c_int = 1073741910;
    // pub const SDLK_KP_PLUS: c_int = 1073741911;
    // pub const SDLK_KP_ENTER: c_int = 1073741912;
    // pub const SDLK_KP_1: c_int = 1073741913;
    // pub const SDLK_KP_2: c_int = 1073741914;
    // pub const SDLK_KP_3: c_int = 1073741915;
    // pub const SDLK_KP_4: c_int = 1073741916;
    // pub const SDLK_KP_5: c_int = 1073741917;
    // pub const SDLK_KP_6: c_int = 1073741918;
    // pub const SDLK_KP_7: c_int = 1073741919;
    // pub const SDLK_KP_8: c_int = 1073741920;
    // pub const SDLK_KP_9: c_int = 1073741921;
    // pub const SDLK_KP_0: c_int = 1073741922;
    // pub const SDLK_KP_PERIOD: c_int = 1073741923;
    // pub const SDLK_APPLICATION: c_int = 1073741925;
    // pub const SDLK_POWER: c_int = 1073741926;
    // pub const SDLK_KP_EQUALS: c_int = 1073741927;
    // pub const SDLK_F13: c_int = 1073741928;
    // pub const SDLK_F14: c_int = 1073741929;
    // pub const SDLK_F15: c_int = 1073741930;
    // pub const SDLK_F16: c_int = 1073741931;
    // pub const SDLK_F17: c_int = 1073741932;
    // pub const SDLK_F18: c_int = 1073741933;
    // pub const SDLK_F19: c_int = 1073741934;
    // pub const SDLK_F20: c_int = 1073741935;
    // pub const SDLK_F21: c_int = 1073741936;
    // pub const SDLK_F22: c_int = 1073741937;
    // ub const SDLK_F23: c_int = 1073741938;
    // pub const SDLK_F24: c_int = 1073741939;
    // pub const SDLK_EXECUTE: c_int = 1073741940;
    // pub const SDLK_HELP: c_int = 1073741941;
    // pub const SDLK_MENU: c_int = 1073741942;
    // pub const SDLK_SELECT: c_int = 1073741943;
    // pub const SDLK_STOP: c_int = 1073741944;
    // pub const SDLK_AGAIN: c_int = 1073741945;
    // pub const SDLK_UNDO: c_int = 1073741946;
    // pub const SDLK_CUT: c_int = 1073741947;
    // pub const SDLK_COPY: c_int = 1073741948;
    // pub const SDLK_PASTE: c_int = 1073741949;
    // pub const SDLK_FIND: c_int = 1073741950;
    // pub const SDLK_MUTE: c_int = 1073741951;
    // pub const SDLK_VOLUMEUP: c_int = 1073741952;
    // pub const SDLK_VOLUMEDOWN: c_int = 1073741953;
    // pub const SDLK_KP_COMMA: c_int = 1073741957;
    // pub const SDLK_KP_EQUALSAS400: c_int = 1073741958;
    // pub const SDLK_ALTERASE: c_int = 1073741977;
    // pub const SDLK_SYSREQ: c_int = 1073741978;
    // pub const SDLK_CANCEL: c_int = 1073741979;
    // pub const SDLK_CLEAR: c_int = 1073741980;
    // pub const SDLK_PRIOR: c_int = 1073741981;
    // pub const SDLK_RETURN2: c_int = 1073741982;
    // pub const SDLK_SEPARATOR: c_int = 1073741983;
    // pub const SDLK_OUT: c_int = 1073741984;
    // pub const SDLK_OPER: c_int = 1073741985;
    // pub const SDLK_CLEARAGAIN: c_int = 1073741986;
    // pub const SDLK_CRSEL: c_int = 1073741987;
    // pub const SDLK_EXSEL: c_int = 1073741988;
    // pub const SDLK_KP_00: c_int = 1073742000;
    // pub const SDLK_KP_000: c_int = 1073742001;
    // pub const SDLK_THOUSANDSSEPARATOR: c_int = 1073742002;
    // pub const SDLK_DECIMALSEPARATOR: c_int = 1073742003;
    // pub const SDLK_CURRENCYUNIT: c_int = 1073742004;
    // pub const SDLK_CURRENCYSUBUNIT: c_int = 1073742005;
    // pub const SDLK_KP_LEFTPAREN: c_int = 1073742006;
    // pub const SDLK_KP_RIGHTPAREN: c_int = 1073742007;
    // pub const SDLK_KP_LEFTBRACE: c_int = 1073742008;
    // pub const SDLK_KP_RIGHTBRACE: c_int = 1073742009;
    // pub const SDLK_KP_TAB: c_int = 1073742010;
    // pub const SDLK_KP_BACKSPACE: c_int = 1073742011;
    // pub const SDLK_KP_A: c_int = 1073742012;
    // pub const SDLK_KP_B: c_int = 1073742013;
    // pub const SDLK_KP_C: c_int = 1073742014;
    // pub const SDLK_KP_D: c_int = 1073742015;
    // pub const SDLK_KP_E: c_int = 1073742016;
    // pub const SDLK_KP_F: c_int = 1073742017;
    // pub const SDLK_KP_XOR: c_int = 1073742018;
    // pub const SDLK_KP_POWER: c_int = 1073742019;
    // pub const SDLK_KP_PERCENT: c_int = 1073742020;
    // pub const SDLK_KP_LESS: c_int = 1073742021;
    // pub const SDLK_KP_GREATER: c_int = 1073742022;
    // pub const SDLK_KP_AMPERSAND: c_int = 1073742023;
    // pub const SDLK_KP_DBLAMPERSAND: c_int = 1073742024;
    // pub const SDLK_KP_VERTICALBAR: c_int = 1073742025;
    // pub const SDLK_KP_DBLVERTICALBAR: c_int = 1073742026;
    // pub const SDLK_KP_COLON: c_int = 1073742027;
    // pub const SDLK_KP_HASH: c_int = 1073742028;
    // pub const SDLK_KP_SPACE: c_int = 1073742029;
    // pub const SDLK_KP_AT: c_int = 1073742030;
    // pub const SDLK_KP_EXCLAM: c_int = 1073742031;
    // pub const SDLK_KP_MEMSTORE: c_int = 1073742032;
    // pub const SDLK_KP_MEMRECALL: c_int = 1073742033;
    // pub const SDLK_KP_MEMCLEAR: c_int = 1073742034;
    // pub const SDLK_KP_MEMADD: c_int = 1073742035;
    // pub const SDLK_KP_MEMSUBTRACT: c_int = 1073742036;
    // pub const SDLK_KP_MEMMULTIPLY: c_int = 1073742037;
    // pub const SDLK_KP_MEMDIVIDE: c_int = 1073742038;
    // pub const SDLK_KP_PLUSMINUS: c_int = 1073742039;
    // pub const SDLK_KP_CLEAR: c_int = 1073742040;
    // pub const SDLK_KP_CLEARENTRY: c_int = 1073742041;
    // pub const SDLK_KP_BINARY: c_int = 1073742042;
    // pub const SDLK_KP_OCTAL: c_int = 1073742043;
    // pub const SDLK_KP_DECIMAL: c_int = 1073742044;
    // pub const SDLK_KP_HEXADECIMAL: c_int = 1073742045;
    // pub const SDLK_LCTRL: c_int = 1073742048;
    // pub const SDLK_LSHIFT: c_int = 1073742049;
    // pub const SDLK_LALT: c_int = 1073742050;
    // pub const SDLK_LGUI: c_int = 1073742051;
    // pub const SDLK_RCTRL: c_int = 1073742052;
    // pub const SDLK_RSHIFT: c_int = 1073742053;
    // pub const SDLK_RALT: c_int = 1073742054;
    // pub const SDLK_RGUI: c_int = 1073742055;
    // pub const SDLK_MODE: c_int = 1073742081;
    // pub const SDLK_AUDIONEXT: c_int = 1073742082;
    // pub const SDLK_AUDIOPREV: c_int = 1073742083;
    // pub const SDLK_AUDIOSTOP: c_int = 1073742084;
    // pub const SDLK_AUDIOPLAY: c_int = 1073742085;
    // pub const SDLK_AUDIOMUTE: c_int = 1073742086;
    // pub const SDLK_MEDIASELECT: c_int = 1073742087;
    // pub const SDLK_WWW: c_int = 1073742088;
    // pub const SDLK_MAIL: c_int = 1073742089;
    // pub const SDLK_CALCULATOR: c_int = 1073742090;
    // pub const SDLK_COMPUTER: c_int = 1073742091;
    // pub const SDLK_AC_SEARCH: c_int = 1073742092;
    // pub const SDLK_AC_HOME: c_int = 1073742093;
    // pub const SDLK_AC_BACK: c_int = 1073742094;
    // pub const SDLK_AC_FORWARD: c_int = 1073742095;
    // pub const SDLK_AC_STOP: c_int = 1073742096;
    // pub const SDLK_AC_REFRESH: c_int = 1073742097;
    // pub const SDLK_AC_BOOKMARKS: c_int = 1073742098;
    // pub const SDLK_BRIGHTNESSDOWN: c_int = 1073742099;
    // pub const SDLK_BRIGHTNESSUP: c_int = 1073742100;
    // pub const SDLK_DISPLAYSWITCH: c_int = 1073742101;
    // pub const SDLK_KBDILLUMTOGGLE: c_int = 1073742102;
    // pub const SDLK_KBDILLUMDOWN: c_int = 1073742103;
    // pub const SDLK_KBDILLUMUP: c_int = 1073742104;
    // pub const SDLK_EJECT: c_int = 1073742105;
    // pub const SDLK_SLEEP: c_int = 1073742106;
    // pub const SDLK_APP1: c_int = 1073742107;
    // pub const SDLK_APP2: c_int = 1073742108;
    // pub const SDLK_AUDIOREWIND: c_int = 1073742109;
    // pub const SDLK_AUDIOFASTFORWARD: c_int = 1073742110;
}

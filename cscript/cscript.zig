const parser = @import("parser.zig");
pub const Parser = parser.Parser;

const compiler = @import("compiler.zig");
pub const JsTargetCompiler = compiler.JsTargetCompiler;

const interpreter = @import("interpreter.zig");
pub const JsValue = interpreter.JsValue;
pub const JsValueType = interpreter.JsValueType;
pub const WebJsValue = interpreter.WebJsValue;
pub const QJS = interpreter.QJS;

const cdata = @import("cdata.zig");
pub const encodeCDATA = cdata.encode;
pub const decodeCDATAdict = cdata.decodeDict;
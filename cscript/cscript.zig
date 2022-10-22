const parser = @import("parser.zig");
pub const Parser = parser.Parser;
pub const ParseResultView = parser.ResultView;
pub const ParseResult = parser.Result;
pub const Node = parser.Node;
pub const NodeId = parser.NodeId;
pub const BinaryExprOp = parser.BinaryExprOp;
pub const FunctionDeclaration = parser.FunctionDeclaration;
pub const FunctionParam = parser.FunctionParam;
pub const Token = parser.Token;
pub const Tokenizer = parser.Tokenizer;
pub const TokenizeState = parser.TokenizeState;
pub const TokenType = parser.TokenType;

const vm_compiler = @import("vm_compiler.zig");
pub const VMcompiler = vm_compiler.VMcompiler;

const js_compiler = @import("js_compiler.zig");
pub const JsTargetCompiler = js_compiler.JsTargetCompiler;
pub const JsTargetResultView = js_compiler.ResultView;

const vm = @import("vm.zig");
pub const VM = vm.VM;
pub const Value = vm.Value;
pub const ByteCodeBuffer = vm.ByteCodeBuffer;
pub const Const = vm.Const;
pub const FuncSymbolEntry = vm.FuncSymbolEntry;
pub const Rc = vm.Rc;
pub const OpCode = vm.OpCode;
pub const OpCount = vm.OpCount;
pub const OpData = vm.OpData;

const interpreter = @import("interpreter.zig");
pub const JsEngine = interpreter.JsEngine;
pub const JsValue = interpreter.JsValue;
pub const JsValueType = interpreter.JsValueType;
pub const WebJsValue = interpreter.WebJsValue;
pub const QJS = interpreter.QJS;

const cdata = @import("cdata.zig");
pub const encodeCDATA = cdata.encode;
pub const decodeCDATAmap = cdata.decodeMap;
pub const EncodeValueContext = cdata.EncodeValueContext;
pub const EncodeMapContext = cdata.EncodeMapContext;
pub const EncodeListContext = cdata.EncodeListContext;
pub const DecodeMapIR = cdata.DecodeMapIR;
pub const DecodeListIR = cdata.DecodeListIR;
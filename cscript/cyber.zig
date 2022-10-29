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

const value = @import("value.zig");
pub const Value = value.Value;
pub const ValuePair = value.ValuePair;
pub const TagFalse = value.TagFalse;
pub const TagTrue = value.TagTrue;
pub const TagNone = value.TagNone;
pub const TagConstString = value.TagConstString;

const vm = @import("vm.zig");
pub const VM = vm.VM;
pub const FuncSymbolEntry = vm.FuncSymbolEntry;
pub const Rc = vm.Rc;
pub const TraceInfo = vm.TraceInfo;
pub const OpCount = vm.OpCount;

const bytecode = @import("bytecode.zig");
pub const ByteCodeBuffer = bytecode.ByteCodeBuffer;
pub const OpCode = bytecode.OpCode;
pub const OpData = bytecode.OpData;
pub const Const = bytecode.Const;

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
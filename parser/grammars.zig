// https://github.com/ziglang/zig-spec/blob/master/grammar/grammar.y
pub const ZigGrammar =
    \\Program { TopLevelStmt* }
    \\TopLevelStmt @inline { StructMember | Statement }
    \\VModifier { 'pub' }
    \\Modifier { 'const' | 'var' }
    \\ExternModifier { 'extern' StringLiteral? }
    \\Statement @inline {
    \\  FunctionDecl | VariableDecl | IfStatement | LabeledStatement |
    \\  TestDecl | DeferStatement | ErrDeferStatement | ExternFunctionDecl | ExternVariableDecl |
    \\  UsingNamespaceStmt | NosuspendBlock | SuspendBlock | BlockStmt | (AssignExpr ';') | (Expression ';')
    \\}
    \\BlockStmt @inline { BlockExpr | WhileStatement | ForStatement | SwitchExpr }
    \\LabeledExpr { Identifier ':' (BlockExpr | WhileExpr) }
    \\LabeledStatement { Identifier ':' BlockStmt }
    \\LabeledTypeExpr { Identifier ':' BlockExpr }
    \\ErrDeferStatement { 'errdefer' (BlockExpr | (AssignExpr ';') | (Expression ';')) }
    \\DeferStatement { 'defer' (BlockExpr | (AssignExpr ';') | (Expression ';')) }
    \\ForStatement { 'inline'? 'for' '(' Expression ')' '|' CaptureParam (',' (Identifier | '_'))? '|' ((BlockExpr ElseStmt?) | (AssignOrExpr (';' | ElseStmt))) }
    \\ForExpr { 'inline'? 'for' '(' Expression ')' '|' CaptureParam (',' (Identifier | '_'))? '|' (BlockExpr | AssignOrExpr ) ElseExpr? }
    \\CaptureParam @inline { ('*'? Identifier) | '_' }
    \\CaptureClause { '|' CaptureParam '|' }
    \\WhileStatement { 'inline'? 'while' '(' Expression ')' CaptureClause? (':' '(' AssignOrExpr ')')? ((AssignOrExpr (';' | ElseIfStmt | ElseStmt)) | (BlockExpr ElseIfStmt?)) }
    \\WhileExpr { 'inline'? 'while' '(' Expression ')' CaptureClause? (':' '(' AssignOrExpr ')')? (BlockExpr | AssignOrExpr) ElseExpr? }
    \\SwitchExpr { 'switch' '(' Expression ')' '{' CaseBranch? (',' CaseBranch)* ','? '}' }
    \\CaseBranch { CaseMatcher '=>' (BlockExpr | AssignOrExpr) }
    \\CaseMatcher { 'else' | (CaseArg (',' CaseArg)* ','?) }
    \\CaseArg { Expression ('...' Expression)? }
    \\IfStatement { 'if' '(' Expression ')' CaptureClause? ((BlockExpr (ElseIfStmt | ElseStmt)?) | (AssignOrExpr (';' | ElseIfStmt | ElseStmt))) }
    \\ElseIfStmt { 'else' CaptureClause? 'if' '(' Expression ')' CaptureClause? ((BlockExpr (ElseIfStmt | ElseStmt)?) | (AssignOrExpr (';' | ElseIfStmt | ElseStmt))) }
    \\ElseStmt { 'else' CaptureClause? (BlockStmt | (AssignOrExpr ';')) }
    \\IfExpr { 'if' '(' Expression ')' CaptureClause? ((BlockExpr (ElseIfExpr | ElseExpr)) | (Expression (ElseIfExpr | ElseExpr)?)) }
    \\ElseIfExpr { 'else' 'if' '(' Expression ')' ((BlockExpr (ElseIfExpr | ElseExpr)) | (Expression (ElseIfExpr | ElseExpr)?)) }
    \\ElseExpr { 'else' Expression }
    \\TryExpr { 'try' Expression }
    \\TestDecl { 'test' StringLiteral? '{' Statement* '}' }
    \\ExternFunctionDecl { VModifier? ExternModifier FunctionType ';' }
    \\FunctionDecl { VModifier? 'export'? 'inline'? 'fn' Identifier '(' Parameters ')' ReturnSignature '{' Statement* '}' }
    \\ExternVariableDecl { VModifier? ExternModifier 'threadlocal'? Modifier Identifier (':' TypeExpr)? ';'}
    \\VariableDecl { VModifier? 'export'? ('comptime' | 'threadlocal')? Modifier Identifier (':' TypeExpr)? LinkSection? Align? '=' Expression ';' }
    \\LinkSection { 'linksection' '(' StringLiteral ')' }
    \\AssignOrExpr @inline { AssignExpr | Expression }
    \\AssignExpr { Expression AssignOp Expression }
    \\ReturnExpr { 'return' Expression? }
    \\BreakExpr { 'break' (':' Identifier)? Expression? }
    \\ContinueExpr { 'continue' (':' Identifier)? }
    \\Expression @inline {
    \\  LabeledExpr | BlockExpr | Identifier | AddressExpr | PropertyAccessExpr | CallExpr | BuiltinCallExpr | ImportExpr | NumberLiteral | FloatLiteral |
    \\  StringLiteral | CharLiteral | TupleLiteral | ErrorLiteral | EnumLiteral | ArrayInitExpr | TupleInitExpr | TypeExpr | BinaryExpr | StructInitExpr | ElementAccessExpr | CatchExpr |
    \\  ComptimeExpr | AsyncExpr | AwaitExpr | ResumeExpr | NosuspendExpr | DereferenceExpr | StructLiteral | IfExpr | WhileExpr | GroupExpr | SwitchExpr | ReturnExpr | 
    \\  UnaryExpr | OrElseExpr | LineStringGroup | 'undefined' | 'unreachable' | ContinueExpr | BreakExpr | TryExpr | '_' | ForExpr | AssemblyExpr
    \\}
    \\TypeExpr @inline { 'void' | 'anytype' | 'anyerror' | 'type' | LabeledTypeExpr | FunctionType | ErrorType | Identifier | PointerType | DoublePointerType | PropertyAccessTypeExpr |
    \\  CallTypeExpr | SliceType | StructTypeExpr | BuiltinCallExpr | OptionalType | ManyItemPointerType | CPointerType | ArrayType | EnumType |
    \\  NumberLiteral | UnionType | GroupTypeExpr | BinaryExpr | SwitchExpr | ErrorSetType | IfExpr | ElementAccessExpr
    \\}
    \\ResumeExpr { 'resume' Expression }
    \\AwaitExpr { 'await' Expression }
    \\AsyncExpr { 'async' Expression }
    \\NosuspendBlock { 'nosuspend' '{' Statement* '}' }
    \\NosuspendExpr { 'nosuspend' Expression }
    \\ComptimeExpr { 'comptime' Expression }
    \\OrElseExpr { Expression 'orelse' Expression }
    \\ElementAccessExpr { Expression '[' Expression ('..' Expression?)? (':' Expression)? ']' }
    \\ArrayInitExpr { '[' ('_' | NumberLiteral) ']' TypeExpr '{' Args '}' }
    \\StructInitExpr { Expression '{' StructMemberInits '}' }
    \\StructMemberInits { StructMemberInit? (',' StructMemberInit)* ','? }
    \\StructMemberInit { '.' Identifier '=' Expression }
    \\AddressExpr { '&' Expression }
    \\SuspendBlock { 'suspend' '{' Statement* '}' }
    \\BlockExpr { 'comptime'? (Identifier ':')? '{' Statement* '}' }
    \\UnaryExpr { ('!' | '-' | '~') Expression }
    \\BinaryExpr { Expression (BinOperator | 'and' | 'or') Expression }
    \\PropertyAccessExpr { Expression '.' (Identifier | '?' | 'type' | 'void' | 'anyerror') }
    \\PropertyAccessTypeExpr { TypeExpr '.' Identifier }
    \\DereferenceExpr { Expression '.*' }
    \\CallTypeExpr { TypeExpr '(' Args ')' }
    \\NumberLiteral { DecLiteral | HexLiteral | OctLiteral | BinLiteral }
    \\ErrorSetType { 'error' '{' EnumMember* '}' }
    \\EnumType { 'enum' ('(' Identifier ')')? '{' EnumMember* '}' }
    \\EnumMember { EnumField | FunctionDecl | VariableDecl | ExternVariableDecl }
    \\EnumField { (((Identifier | 'type') ('=' Expression)?) | '_') ','? }
    \\OptionalType { '?' TypeExpr }
    \\DoublePointerType { '**' 'allowzero'? 'volatile'? Align? 'const'? 'volatile'? TypeExpr }
    \\PointerType { '*' 'allowzero'? 'volatile'? Align? 'const'? 'volatile'? TypeExpr }
    \\Align { 'align' '(' Expression ')' }
    \\SliceType { '[' SentinelTerminated? ']' 'allowzero'? 'volatile'? Align? 'const'? TypeExpr }
    \\ArrayType { '[' Expression SentinelTerminated? ']' 'const'? TypeExpr }
    \\ManyItemPointerType { '[' '*' SentinelTerminated? ']' 'allowzero'? 'volatile'? Align? 'const'? TypeExpr }
    \\CPointerType { '[' '*' IdentifierToken='c' ']' 'allowzero'? Align? 'const'? 'volatile'? TypeExpr }
    \\SentinelTerminated { ':' TypeExpr }
    \\FunctionType { 'fn' Identifier? '(' TypeParameters ')' ReturnSignature }
    \\TypeParameters { TypeParameter? (',' TypeParameter)* ','? }
    \\TypeParameter { (((Comptime | 'noalias')? Identifier ':')? TypeExpr) | '...' }
    \\BuiltinCallExpr { (AtIdentifier | BuiltinLiteral) '(' Args ')' }
    \\GroupExpr { '(' Expression ')' }
    \\GroupTypeExpr { '(' TypeExpr ')' }
    \\CallExpr { Expression '(' Args ')' }
    \\CatchExpr { Expression 'catch' CaptureClause? Expression }
    \\ImportExpr { '@import' '(' StringLiteral ')' }
    \\ReturnSignature { CallConvention? Align? TypeExpr }
    \\CallConvention { 'callconv' '(' Expression ')' }
    \\UnionType { 'extern'? 'packed'? 'union' ('(' ('enum' | TypeExpr) ')')? '{' UnionMember* '}' Align? }
    \\UnionMember @inline { FunctionDecl | ExternFunctionDecl | VariableDecl | ExternVariableDecl | StructField | EnumField }
    \\StructTypeExpr { ('extern' | 'packed')? 'struct' '{' StructMember* '}' }
    \\StructMember @inline { UsingNamespaceStmt | FunctionDecl | ExternFunctionDecl | VariableDecl | ExternVariableDecl | StructField | (&'comptime' BlockExpr) }
    \\StructField { 'comptime'? (Identifier | 'type' | '_') ':' TypeExpr Align? ('=' Expression)? ','? }
    \\AssemblyExpr { 'asm' 'volatile'? '(' AsmCode (':' AsmOutputs? (':' AsmInputs? (':' AsmClobbers)?)?)? ')' }
    \\AsmCode { StringLiteral | LineStringGroup }
    \\AsmOutputs { AsmOutput (',' AsmOutput)* ','? }
    \\AsmOutput { '[' (Identifier | '_') ']' StringLiteral '(' (Identifier | ('->' Expression)) ')' }
    \\AsmInputs { AsmInput (',' AsmInput)* ','? }
    \\AsmInput { '[' (Identifier | '_') ']' StringLiteral '(' Expression ')' }
    \\AsmClobbers { StringLiteral (',' StringLiteral)* }
    \\UsingNamespaceStmt { VModifier? 'usingnamespace' Expression ';' }
    \\TupleInitExpr { Expression '{' Args '}' }
    \\TupleLiteral { '.' '{' Args '}' }
    \\StructLiteral { '.' '{' StructMemberInits '}' }
    \\EnumLiteral { '.' Identifier }
    \\ErrorLiteral { 'error' '.' Identifier }
    \\Args { Expression? (',' Expression)* ','? }
    \\Parameters { Parameter? (',' Parameter)* ','? }
    \\Parameter { ((Comptime | 'noalias')? (Identifier | '_') ':' TypeExpr) | '...' }
    \\ErrorType { ('anyerror' | ErrorSetType | ErrorLiteral | (!'!' Expression))? '!' TypeExpr }
    \\Comptime { 'comptime' }
    \\Identifier @inline { IdentifierToken | AtStringIdentifier }
    \\LineStringGroup { LineString+ }
    \\FloatLiteral { DecFloatLiteral | HexFloatLiteral }
    \\AssignOp { '=' | '+=' | '-=' | '*=' | '/=' | '|=' | '&=' | '%=' | '>>=' | '<<=' | '^=' }
    \\@tokens {
    \\  Comment @skip { '//' [^\n]* '\n' }
    \\  BinLiteral { '0b' ('_'? [0-1]+)+ }
    \\  HexFloatLiteral { HexLiteral (('.' [0-9a-fA-F]+ ([pP] [+\-]? DecLiteral)?) | ([pP] [+\-]? DecLiteral))  }
    \\  HexLiteral { '0x' ('_'? [0-9a-fA-F]+)+ }
    \\  OctLiteral { '0o' [0-7]+ }
    \\  DecFloatLiteral { DecLiteral (('.' DecLiteral ([eE] [+\-]? DecLiteral)?) | ([eE] [+\-]? DecLiteral))  }
    \\  DecLiteral { [0-9] ('_'? [0-9]+)* }
    \\  CharLiteral { '\'' ('\\\\' | '\\\'' | [^\n'])+ '\'' }
    \\  StringLiteral { '"' ('\\\\' | '\\"' | [^\n"])* '"' }
    \\  LineString { '\\\\' [^\n]* '\n' }
    \\  IdentifierToken { [a-zA-Z_] [a-zA-Z0-9_]* }
    \\  Keyword @literal @replace(IdentifierToken) {
    \\    'fn' | 'return' | 'const' | 'var' | 'pub' | 'try' | 'comptime' | 'type' | 'struct' | 'anytype' | 'void' |
    \\    'if' | 'else' | 'for' | 'break' | 'callconv' | 'catch' | 'unreachable' | '_' | 'while' | 'and' | 'or' |
    \\    'usingnamespace' | 'inline' | 'test' | 'defer' | 'enum' | 'extern' | 'union' | 'switch' | 'align' | 'packed' |
    \\    'orelse' | 'noalias' | 'threadlocal' | 'undefined' | 'errdefer' | 'error' | 'nosuspend' | 'anyerror' | 'async' | 'await' |
    \\    'suspend' | 'resume' | 'continue' | 'asm' | 'volatile' | 'export' | 'linksection' | 'allowzero'
    \\  }
    \\  AtIdentifier { '@' IdentifierToken }
    \\  AtStringIdentifier { '@' StringLiteral }
    \\  BuiltinLiteral @literal @replace(AtIdentifier) {
    \\    '@import' | '@This'
    \\  }
    \\  BinOperator @literal { '+=' | '++' | '+' | '->' | '-=' | '-' | '*=' | '/=' | '|=' | '**' | '<=' | '>=' | '>>=' | '>>' | '<<=' | '<<' | '&=' | '%=' |
    \\    '==' | '!=' | '<' | '>' | '*' | '/' | '&' | '|' | '%' | '^=' | '^' | '~'
    \\  }
    \\  Operator @literal { '...' | '..' | '.*' | '=>' | '=' }
    \\  Punctuator @literal { '(' | ')' | '{' | '}' | ';' | ':' | '!' | '.' | ',' | '[' | ']' |
    \\    '?'
    \\  }
    \\}
;

// https://github.com/tree-sitter/tree-sitter-javascript/blob/master/grammar.js
// https://github.com/tree-sitter/tree-sitter-typescript/blob/master/common/define-grammar.js
// https://github.com/lezer-parser/javascript/blob/main/src/javascript.grammar
// https://ts-ast-viewer.com/
// TODO: Typescript/js grammar
pub const TypescriptGrammar =
    \\
;

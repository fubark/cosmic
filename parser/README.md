# Parser

An interpreted parser that generates grammars at runtime from PEG like config files and parses source files into an AST. The goal is to also implement incremental parsing for use in text editors.
- Parses in linear time using a match rule cache.
- Supports left recursion
- Supports look-ahead operators
- Initial support for incremental retokenize. *Still work to be done on the incremental AST reparse*

## Example

A full example config that parses Zig code can be found [here](https://github.com/fubark/cosmic/blob/master/parser/grammars.zig).

Here is a demo that parses all the zig stdlib sources.
You will need zig installed and also *REPO/lib/zig* should point to zig's source repo:
```sh
zig build test-file -Dpath=parser/parser_manual.test.zig -Drelease-safe
```

## Creating Grammars

The config format is easy to read and write. Here are some common things you might declare:

### Rules
Rules contain match terms. Token rules are declared in a @tokens block and match in the order they were declared. AST rules are declared at the top level and the order doesn't matter since parsing requires a root rule:

```
ReturnExpr { Identifier='return' Identifier }
@tokens {
    Identifier { [a-zA-Z] [a-zA-Z0-9_]* }
}
```

### Match token literals
If you use string literals in AST rules, you'll need to declare the token to be a literal. This makes the matching really fast. *Only static token rules like Operator can be made into a literal, so Identifier can not*:
```
AddExpr { Identifier '+' Identifier }
@tokens {
    Identifier { [a-zA-Z] [a-zA-Z0-9_]* }
    Operator @literal { '+' }
}
```

### Replace tokens
When you already parsed a generic token like Identifier but you want to replace it conditionally afterwards, use @replace. *Currently, replace rules also need to be literals*:
```
@tokens {
    Identifier { [a-zA-Z_] [a-zA-Z0-9_]* }
    Keyword @literal @replace(Identifier) {
        'if' | 'else' | 'var' | 'struct'
    }
}
```

### Skip tokens
Token rules marked with @skip will match them and continue without feeding it to the AST parser:
```
@tokens {
    Comment @skip { '//' [^\n]* '\n' }
}
```

### Match text
Text match terms are enclosed with single quotes. Inside, you'll need to escape single quotes, backslashes, and control characters with a backslash. Char sets are enclosed in brackets. You can have a series of accepted characters or a char range. "^" at the beginning turns it into a negated char set:
```
@tokens {
    DecLiteral { [0-9] ('_'? [0-9]+)* }
    StringLiteral { '"' ('\\\\' | '\\"' | [^\n"])* '"' }
}
```

### Match a sequence or choice
By default, adjacent terms are matched as a sequence. If one of them fails to match the entire rule fails. Inserting "|" in between turns it into a choice match. Starting from the leftmost term, it will return the first term that matches. If none of them match, the rule fails. Inserting parentheses will group terms together:
```
SomeSeq { First Second Third }
SomeChoice { ChoiceA | ChoiceB | ChoiceC }
Compound { (First Second) | (Left Right) }
```

### Match repetitions
Terms can end with a repetition operator. "?" for optional. "+" to match one or more, and "*" to match zero or more:
```
DecLiteral { [0-9] ('_'? [0-9]+)* }
```

### Inline rules
Some rules are meant to be a parent class of several different rules. Use @inline if you want it to skip creating the parent node and instead return the matching child node:
```
Expression @inline { BinaryExpression | CallExpression | Identifier }
```

### Left recursion
A rule is left recursive if a sub rule has a left term that matches the rule again. The parser detects this and will repeatedly reparse those sub rules with the currently matched left term. If you wanted to parse this into a nested expression:
```
1 + 2 + 3 + 4
```
You might write the rules like this:
```
Expression { NumberLiteral | BinaryExpr }
BinaryExpr { Expression '+' Expression }
```
The "1" is parsed as NumberLiteral at first but before returning the Expression it's reparsed as a BinaryExpr because the leftmost term of BinaryExpr is an Expression. This will continue until it can't reparse and consume more tokens.

### Look-ahead terms
Look-ahead terms match just like normal terms but they won't advance the parser position. Prefixing a term with "&" makes it a positive lookahead. If the term matches it will continue on to the next term without consuming any tokens. "!" makes it a negative lookahead so the term must not match before continuing:
```
ReturnType { (!'!' Expression)? '!' Expression }
SpecialFunction { &SpecialPrefix 'fn' SpecialBody }
```

## Usage

See the test files on how to use the parser in zig code. The "parseDebug" entry point is slower but it provides metrics and error reporting.
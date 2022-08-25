# CScript

CScript (name is subject to change) will be the primary scripting language used in Cosmic.
It is currently transpiled to JavaScript to run on the web. On desktop, it uses the QuickJs engine as a prototype (this is temporary).

NOTE: A lot of the language described here has not been implemented yet.

CScript is easy to learn. Here is an overview of the language:

### Goals
Some features that CScript will explore:
- Reactive programming. The ability to recompute/subscribe functions when variable dependencies are updated at runtime.
- Coroutines. The ability to pause execution of a function and resume it later on.
- Gas metering. Ability for execution to yield after running for too long.
- Gradual typing.
- Initially implemented as an interpreted language.
- Custom language semantics. Operator overloading.
- Readability. The syntax is inspired by python where braces are omitted for statement bodies and indentation determines which block a statement belongs to.
- Intended to be edited by the Cosmic editor. Not necessarily optimized for editing from a general purpose text editor.
- Other features that may be needed by the Cosmic editor.

### Hello World
```cscript
cs.log 'Hello World!'
```

### Data Types
TODO

### Variables
TODO

### Strings
```cscript
// Single line string literal.
apple = 'a fruit'

// There are two methods to write a multiple line string literal. 
// The recommended way is to use quotes to clearly show the whitespace surrounding a line.
poem =: 'one semicolon'
    'two blobs missing from a screen'
    'hours of life lost'

// The other method is to use backticks.
poem = `one semicolon
two blobs missing from a screen
hours of life lost`
```

### Arrays
```cscript
arr = [ 1, 2, 3 ]
cs.log arr[0]
```

### Dictionaries
```cscript
dict = { a: 123, b: fun () => 5 }
cs.log dict.a
cs.log dict['a']
```

### Branching
Use `if`, `elif`, `else` to branch the execution of your code depending on conditions:
```cscript
a = 10
if a == 10:
    cs.log 'a is 10'
elif a == 20:
    cs.log 'a is 20'
else:
    cs.log 'neither 10 nor 20'
```
A single line `if` expression also needs the `then` keyword:
```cscript
a = 10
str = if a == 10 then 'red' elif a == 20 then 'green' else 'blue'
```

### Labels
TODO

### Loops and iteration
Loops and iterations start with the `for` keyword. An infinite loop continues to run the code in the block until a `break` or `return` is reached. When the `for` clause contains a condition, the loop continues to run until the condition is evaluated to false.
```cscript
for: // Infinite loop.
    nop

running = true
for running: // Keep looping until `running` is false.
    nop
```
`for` loops can iterate over a range that starts at a number (inclusive) to a target number (exclusive). Note that by default the looping counter is incremented by one:
```cscript
for 0..100 of i:
    cs.log i    // 0, 1, 2, ... , 99

for 0..100, 10 of i:
    cs.log i    // 0, 10, 20, ... , 90

for 100..0, -1 of i:
    cs.log i    // 100, 99, 98, ... , 1
```
TODO: Iterating arrays.

TODO: Iterating dictionaries.
### Matching
```cscript
val = 1000
match val:
    0..100: cs.log 'at or between 0 and 99'
    100: cs.log 'val is 100'
    200:
        cs.log 'val is 200'
    else:
        cs.log 'val is' val
```

### Functions
Functions are declared with the `fun` keyword:
```cscript
using cs.math
fun dist(x0, y0, x1, y1):
    dx = x0-x1
    dy = y0-y1
    return sqrt dx*dx+dy*dy
```
There are two methods to call functions. The concise method is to use parentheses:
```cscript
d = dist(100, 100, 200, 200)
```
The shorthand method omits parentheses and commas. Args are separated by whitespace. A string can contain whitespace since it's surrounded by `'` delimiters. The shorthand only works for functions that accept parameters:
```cscript
d = dist 100 100 200 200 // Calls the function `dist`.

fun random():            // Function with no parameters.
    return 4

r = random               // Returns the function itself as a value. Does not call the function `random`.
r = random()             // Calls the function `random`.
```
You can call functions with named parameters.
```cscript
d = dist(x0: 10, x1: 20, y0: 30, y1: 40)
```
Functions can return multiple values:
```cscript
using cs.math
fun compute(rad):
    return cos(rad), sin(rad)
x, y = compute(pi)
```

### Lambdas
```cscript
// Single line lambda.
canvas.onUpdate(fun (delta_ms) => print delta_ms)

// Multi line lambda.
canvas.onUpdate(
    fun (delta_ms):
        print delta_ms
)
```

### Closures
TODO

### Exceptions and errors.
TODO

### Coroutines
TODO

### Reactive Variables
TODO

### Import, Export
TODO

### Use namespace
TODO

### Annotations
TODO

### Access Control
Declarations are all public. Fields and declarations can have a private annotation but it isn't enforced and only serves to ignore the autocompletion in the code editor.
<details>
<summary>Explain</summary>
The author may not know all use cases of their library so this removes friction for users to access the library internals.
</details>

### Operator Overloading
Custom logic for operators can be declared in a `language` definition.
```cscript
language math:
    fun +(left, right):
        return Vec2{ x: left.x + right.x, y: left.y + right.y }

vec3 = math# vec1 + vec2
vec3 = math#:
    vec1 + vec2
```

### Gas Meters
TODO

### Visualization
TODO

### Comments
TODO

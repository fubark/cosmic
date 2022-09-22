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

// Escape the single quote to use it inside the string or use backticks.
apple = 'Bob\'s fruit'
apple = `Bob's fruit`

// Unicode.
str = 'abc🦊xyz🐶'

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

### Lists
```cscript
list = [ 1, 2, 3 ]
cs.log list[0]
```

Lists can be sliced with the range `..` clause:
```cscript
list = [ 1, 2, 3, 4, 5 ]
list[0..0]  // []          Empty list.
list[0..3]  // [ 1, 2, 3 ] From start to end index.
list[3..]   // [ 4, 5 ]    From start index to end of list. 
list[..3]   // [ 1, 2, 3 ] From start of list to end index.
list[2..+2] // [ 3, 4 ]    From start index to start index + length.
```

### Dictionaries
```cscript
dict = { a: 123, b: func () => 5 }
cs.log dict.a
cs.log dict['a']

// Dictionaries entries can be separated by the new line.
map = {
    foo: 1
    bar: 2
}

// Entries can also follow a `{}:` block.
colors = {}:
    red: 0xFF0000
    green: 0x00FF00
    blue: 0x0000FF

    // This pattern can also be used in child entries like this.
    darker {}: 
        red: 0xAA0000
        green: 0x00AA00
        blue: 0x0000AA
```

### Branching
Use `if` and `else` to branch the execution of your code depending on conditions:
```cscript
a = 10
if a == 10:
    cs.log 'a is 10'
else a == 20:
    cs.log 'a is 20'
else:
    cs.log 'neither 10 nor 20'
```
A single line `if` expression also needs the `then` keyword. `else` condition is not allowed in single line `if` expressions.:
```cscript
a = 10
str = if a == 10 then 'red' else 'blue'
```

### Labels
TODO

### Loops and iteration
Loops and iterations start with the `for` keyword. An infinite loop continues to run the code in the block until a `break` or `return` is reached. When the `for` clause contains a condition, the loop continues to run until the condition is evaluated to false.
```cscript
for: // Infinite loop.
    pass

running = true
for running: // Keep looping until `running` is false.
    pass
```
`for` loops can iterate over a range that starts at a number (inclusive) to a target number (exclusive). Note that by default the looping counter is incremented by one:
```cscript
for 0..100 as i:
    cs.log i    // 0, 1, 2, ... , 99

for 0..100 as i += 10:
    cs.log i    // 0, 10, 20, ... , 90

for 100..0 as i -= 1:
    cs.log i    // 100, 99, 98, ... , 1

for 100..=0 as i -= 1:
    cs.log i    // 100, 99, 98, ... , 0
```
Iterating lists.
```cscript
list = [1, 2, 3, 4, 5]

// Iterate on values.
for list as n:
    cs.log n

// Iterate on values and indexes.
for list as n, i:
    cs.log n, i 

// Iterate on just indexes.
for list as _, i:
    cs.log i 
```
Iterating dictionaries.
```cscript
dict = { a: 123, b: 234 }

// Iterate on values.
for dict as v:
    cs.log v

// Iterate on values and keys.
for dict as v, k:
    cs.log v, k

// Iterate on just keys.
for dict as _, k:
    cs.log k
```

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

#### Declaring functions.
Functions are declared with the `func` keyword. Functions declared in the top level scope are eligible for hot swap during development.
```cscript
using cs.math
func dist(x0, y0, x1, y1):
    dx = x0-x1
    dy = y0-y1
    return sqrt dx*dx+dy*dy
```
Functions can return multiple values:
```cscript
using cs.math
func compute(rad):
    return cos(rad), sin(rad)
x, y = compute(pi)
```

#### Calling functions.
There are two methods to call functions. The concise method is to use parentheses:
```cscript
d = dist(100, 100, 200, 200)
```
The shorthand method omits parentheses and commas. Args are separated by whitespace. A string can contain whitespace since it's surrounded by `'` delimiters. The shorthand only works for functions that accept parameters:
```cscript
d = dist 100 100 200 200 // Calls the function `dist`.

func random():            // Function with no parameters.
    return 4

r = random               // Returns the function itself as a value. Does not call the function `random`.
r = random()             // Calls the function `random`.
```
You can call functions with named parameters.
```cscript
d = dist(x0: 10, x1: 20, y0: 30, y1: 40)
```

### Lambdas
```cscript
// Single line lambda.
canvas.onUpdate(func (delta_ms) => print delta_ms)

// Multi line lambda.
canvas.onUpdate(
    func (delta_ms):
        print delta_ms
)
```
Lambdas can also be declared and assigned to a nested property of an existing variable. A declaration at the top level scope also makes the lambda eligible for hot swap during development.
```cscript
dict = {}
func dict.foo():
    return 123
dict.foo()

// Equivalent to:
dict = {}
dict.foo = func () => 123
dict.foo()
```

### Closures
TODO

### Exceptions and errors.
TODO

### Async
An async task can be created using `@asyncTask()`. Code can suspend on an `apromise` and wait for the value to resolve with `await`.
```cscript
func foo():
    task = @asyncTask()
    @queueTask(func () => task.resolve(123))
    return task.promise
await foo()
// Returns 123.
```

When the function is declared to return an `apromise`. Callers can omit the `await` keyword:
```cscript
func foo() apromise:
    task = @asyncTask()
    @queueTask(func () => task.resolve(123))
    return task.promise
1 + foo()
// Returns 124. Equivalent to "1 + await foo()".
```

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
Declarations are all public. Fields and declarations can have a `@private` annotation but it isn't enforced and only serves to ignore the autocompletion in the code editor.

<details>
<summary>Explain</summary>
The author may not know all use cases of their library so this removes friction for users to access the library internals.
</details>

### Operator Overloading
Custom logic for operators can be declared in a `language` definition.
```cscript
language math:
    func +(left, right):
        return Vec2{ x: left.x + right.x, y: left.y + right.y }

vec3 = math# vec1 + vec2
vec3 = math#:
    vec1 + vec2
```

### CDATA: CScript Data Format
Similar to JSON/JavaScript, the CDATA format uses the same literal value semantics as CScript.
```cscript
{
    name: 'John Doe'
    'age': 25
    cities: [
        'New York'
        'San Francisco'
        'Tokyo'
    ]
}
```

### Gas Meters
TODO

### Visualization
TODO

### Comments
TODO

# SwiftMQuickJS

A Swift package that wraps the [mquickjs](https://github.com/bellard/mquickjs) JavaScript engine with a clean, JavaScriptCore-like API for iOS and macOS.

## Overview

SwiftMQuickJS provides a Swift-friendly interface to mquickjs, a minimal JavaScript engine designed for embedded systems. It's perfect for executing custom JavaScript in resource-constrained environments like iOS/macOS apps where you need to run user scripts or add scripting capabilities.

### Key Features

- ✅ **JavaScriptCore-like API** - Familiar MQJSContext and MQJSValue classes
- ✅ **Automatic Memory Management** - Configurable memory allocation with RAII cleanup
- ✅ **GC Safety** - Proper handling of mquickjs's moving garbage collector
- ✅ **Type Conversion** - Seamless Swift ↔ JavaScript type conversion
- ✅ **Native Function Binding** - Call Swift functions from JavaScript
- ✅ **Custom Class Registration** - Expose Swift classes to JavaScript with `new`
- ✅ **Error Handling** - Swift throws/catch pattern for JavaScript exceptions
- ✅ **Small Footprint** - mquickjs uses ~10KB RAM for basic execution
- ✅ **Full Standard Library** - Date, RegExp, Math, JSON, and more

## Installation

Add SwiftMQuickJS to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/PasiSalenius/SwiftMQuickJS", from: "1.0.0")
]
```

## Quick Start

### Basic Script Evaluation

```swift
import MQuickJS

// Create a JavaScript context
let context = try MQJSContext()

// Evaluate JavaScript code
let result = try context.eval("1 + 2")
print(try result.toInt32()) // Prints: 3

// Evaluate expressions
let greeting = try context.eval("'Hello, ' + 'World!'")
print(try greeting.toString()) // Prints: "Hello, World!"
```

### Working with Objects

```swift
// Create and access JavaScript objects
let person = try context.eval("""
    ({
        name: 'Alice',
        age: 30,
        greet: function() {
            return 'Hello, ' + this.name;
        }
    })
""")

// Access properties
let name = person["name"]
print(try name?.toString()) // Prints: "Alice"

let age = person["age"]
print(try age?.toInt32()) // Prints: 30

// Call methods
let greeting = try person["greet"]?.call(withArguments: nil)
print(try greeting?.toString()) // Prints: "Hello, Alice"
```

### Working with Arrays

```swift
// Create arrays
let numbers = try context.eval("[1, 2, 3, 4, 5]")

// Access by index
let first = numbers[0]
print(try first?.toInt32()) // Prints: 1

// Get array length
let length = numbers["length"]
print(try length?.toInt32()) // Prints: 5
```

### Global Variables

```swift
// Set global variables
try context.eval("var x = 42")
try context.eval("var name = 'SwiftMQuickJS'")

// Access globals through globalObject
let global = context.globalObject
let x = global["x"]
print(try x?.toInt32()) // Prints: 42

// Set globals from Swift
global["myValue"] = try 100.toJSValue(in: context)
let result = try context.eval("myValue * 2")
print(try result.toInt32()) // Prints: 200
```

### Type Conversion

SwiftMQuickJS automatically converts between Swift and JavaScript types:

```swift
// Swift → JavaScript
let swiftInt = 42
let swiftString = "Hello"
let swiftDouble = 3.14
let swiftBool = true

let jsInt = try swiftInt.toJSValue(in: context)
let jsString = try swiftString.toJSValue(in: context)
let jsDouble = try swiftDouble.toJSValue(in: context)
let jsBool = try swiftBool.toJSValue(in: context)

// JavaScript → Swift
let jsResult = try context.eval("Math.PI")
let piValue: Double = try jsResult.toDouble() // 3.141592653589793

// Arrays and Dictionaries
let swiftArray = [1, 2, 3, 4, 5]
let jsArray = try swiftArray.toJSValue(in: context)

let swiftDict = ["name": "Alice", "city": "NYC"]
let jsObject = try swiftDict.toJSValue(in: context)
```

### Error Handling

```swift
do {
    // This will throw a JavaScript error
    let result = try context.eval("undefined.foo()")
} catch let error as MQJSError {
    print("JavaScript error: \(error.localizedDescription)")
}

// Catch syntax errors
do {
    let result = try context.eval("function broken(")
} catch MQJSError.evaluationError(let message) {
    print("Syntax error: \(message)")
}
```

### Native Functions (Swift → JavaScript)

Register Swift functions that can be called from JavaScript:

```swift
// Register a simple function
try context.setFunction("greet") { args in
    let name = try args[0].toString()
    return "Hello, \(name)!"
}

let result = try context.eval("greet('World')")
print(try result.toString()) // Prints: "Hello, World!"

// Register a function with multiple arguments
try context.setFunction("add") { args in
    let a = try args[0].toInt32()
    let b = try args[1].toInt32()
    return a + b
}

let sum = try context.eval("add(5, 3)")
print(try sum.toInt32()) // Prints: 8

// Functions can return complex types
try context.setFunction("getPerson") { _ in
    return ["name": "Alice", "age": 30] as [String: Any]
}

// Functions can capture Swift state
var counter = 0
try context.setFunction("increment") { _ in
    counter += 1
    return counter
}
```

### Custom Class Registration

Expose Swift classes to JavaScript with full constructor and method support:

```swift
// Define a Swift class
class Counter {
    var value: Int

    init(start: Int = 0) {
        self.value = start
    }

    func increment() {
        value += 1
    }

    func getValue() -> Int {
        return value
    }
}

// Register the class with JavaScript
try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
    builder.constructor { args in
        let start = (try? args.first?.toInt32()) ?? 0
        return Counter(start: Int(start))
    }
    builder.method("increment") { this, args in
        this.increment()
        return nil
    }
    builder.method("getValue") { this, args in
        return this.getValue()
    }
}

// Use from JavaScript
let result = try context.eval("""
    var c = new Counter(10);
    c.increment();
    c.increment();
    c.getValue();
""")
print(try result.toInt32()) // Prints: 12

// Multiple instances are independent
let multiResult = try context.eval("""
    var c1 = new Counter(0);
    var c2 = new Counter(100);
    c1.increment();
    c1.getValue() + c2.getValue();
""")
print(try multiResult.toInt32()) // Prints: 101
```

**Note:** mquickjs uses ES5 syntax, so JavaScript code must use `var` instead of `let`/`const`.

### Memory Management

```swift
// Default: 1MB memory
let context1 = try MQJSContext()

// Custom memory size
let context2 = try MQJSContext(memorySize: 256 * 1024) // 256KB

// Use predefined sizes
let simpleContext = try MQJSContext(
    memorySize: MQJSContext.memoryForSimpleScripts // 64KB
)

let devContext = try MQJSContext(
    memorySize: MQJSContext.memoryForDevelopment // 4MB
)

// Manual garbage collection (rarely needed)
context.collectGarbage()
```

## Architecture

### Memory Management

SwiftMQuickJS handles mquickjs's unique memory model:

- **Pre-allocated Buffer**: Memory is allocated upfront and never grows
- **Moving GC**: Objects can relocate during garbage collection
- **JSGCRef Protection**: All MQJSValue instances maintain GC references to prevent collection

### Thread Safety

**Not thread-safe.** Create separate contexts per thread or synchronize access:

```swift
// Option 1: Separate contexts per thread
DispatchQueue.global().async {
    let context = try! MQJSContext()
    let result = try! context.eval("1 + 2")
}

// Option 2: Serial queue
let jsQueue = DispatchQueue(label: "com.myapp.js")
let context = try! MQJSContext()

jsQueue.async {
    let result = try! context.eval("1 + 2")
}
```

### Lifecycle

```swift
// Contexts automatically clean up when deallocated
func executeScript() {
    let context = try! MQJSContext()
    let result = try! context.eval("42")
    // context deallocates here, freeing all resources
}

// Values become invalid when context deallocates
let value: MQJSValue
do {
    let context = try! MQJSContext()
    value = try! context.eval("42")
} // context deallocates
// value is now invalid - don't use it!
```

## API Reference

### MQJSContext

The main JavaScript execution context.

#### Initialization

```swift
init(memorySize: Int = defaultMemorySize) throws
```

**Parameters:**
- `memorySize`: Size of memory buffer in bytes (default: 1MB, minimum: 64KB)

**Predefined Sizes:**
- `MQJSContext.memoryForSimpleScripts` - 64KB
- `MQJSContext.memoryForModerateScripts` - 256KB
- `MQJSContext.memoryForComplexScripts` - 1MB (default)
- `MQJSContext.memoryForDevelopment` - 4MB

#### Methods

```swift
func eval(_ script: String, filename: String = "<eval>", flags: Int32 = JS_EVAL_RETVAL) throws -> MQJSValue
```

Evaluates JavaScript code and returns the result.

```swift
func parse(_ script: String, filename: String = "<parse>", flags: Int32 = JS_EVAL_RETVAL) throws -> MQJSValue
```

Parses JavaScript without executing (for precompilation).

```swift
func run(_ compiledFunction: MQJSValue) throws -> MQJSValue
```

Runs a previously parsed function.

```swift
func collectGarbage()
```

Manually triggers garbage collection.

```swift
func setFunction(_ name: String, _ function: @escaping ([MQJSValue]) throws -> Any?) throws
```

Registers a Swift function callable from JavaScript.

```swift
func registerClass<T: AnyObject>(_ name: String, configure: (MQJSClassBuilder<T>) -> Void) throws
```

Registers a Swift class that can be instantiated from JavaScript with `new`.

#### Properties

```swift
var globalObject: MQJSValue { get }
```

The JavaScript global object (access `globalThis`).

### MQJSValue

A JavaScript value wrapper with automatic GC management.

#### Type Checking

```swift
var isUndefined: Bool { get }
var isNull: Bool { get }
var isBool: Bool { get }
var isNumber: Bool { get }
var isString: Bool { get }
var isObject: Bool { get }
var isFunction: Bool { get }
var isArray: Bool { get }
```

#### Type Conversion

```swift
func toInt32() throws -> Int32
func toDouble() throws -> Double
func toString() throws -> String
func toBool() throws -> Bool
```

#### Property Access

```swift
subscript(property: String) -> MQJSValue?  // object["key"]
subscript(index: Int) -> MQJSValue?        // array[0]
```

### MQJSConvertible Protocol

Implement this protocol to convert Swift types to JavaScript:

```swift
protocol MQJSConvertible {
    func toJSValue(in context: MQJSContext) throws -> MQJSValue
}
```

Built-in conformances: `Int`, `Int32`, `UInt32`, `Double`, `Float`, `String`, `Bool`, `Array`, `Dictionary`, `Optional`

### MQJSInitializable Protocol

Implement this protocol to convert JavaScript types to Swift:

```swift
protocol MQJSInitializable {
    init(from jsValue: MQJSValue) throws
}
```

### MQJSClassBuilder

Builder for defining Swift classes exposed to JavaScript.

```swift
class MQJSClassBuilder<T: AnyObject> {
    func constructor(_ fn: @escaping ([MQJSValue]) throws -> T) -> Self
    func method(_ name: String, _ fn: @escaping (T, [MQJSValue]) throws -> Any?) -> Self
}
```

**Methods:**
- `constructor`: Define how instances are created (receives JS arguments, returns Swift instance)
- `method`: Define instance methods (receives Swift instance and JS arguments)

### MQJSError

Error types thrown by SwiftMQuickJS:

```swift
enum MQJSError: Error {
    case invalidMemorySize(Int)
    case contextCreationFailed
    case invalidContext
    case invalidValue
    case evaluationError(String)
    case typeConversionError(String)
    case nativeFunctionError(String)
    case classRegistrationError(String)
    case notAFunction
    case notAnObject
    case stackOverflow
}
```

## Example: Data Transformation

Use JavaScript to transform data structures:

```swift
import MQuickJS

class DataTransformer {
    let context: MQJSContext

    init() throws {
        context = try MQJSContext(memorySize: MQJSContext.memoryForModerateScripts)

        // Load transformation script
        try context.eval("""
            function transform(data) {
                // User-defined transformation logic
                data.processed = true;
                data.timestamp = Date.now();
                return data;
            }
        """)
    }

    func transform(data: [String: Any]) throws -> [String: Any] {
        let result = try context.callFunction("transform", withArguments: [data])
        return try result.toDictionary()
    }
}
```

## Performance

- **Context creation**: ~1ms
- **Simple eval**: ~0.1ms
- **Memory footprint**: Configurable (64KB - 4MB+)
- **Startup size**: ~200KB binary size increase

## Limitations

### Current Version

- ❌ Modules (import/export) - mquickjs limitation
- ❌ Promises/async-await - Not supported by mquickjs
- ❌ setTimeout/setInterval - Not supported in embedded mode
- ❌ ES6+ syntax (`let`, `const`, arrow functions) - mquickjs uses ES5

### By Design

- Single-threaded (mquickjs limitation)
- Fixed memory size (no dynamic growth)
- No JIT compilation (interpreted only)
- Classes must be reference types (AnyObject)

## Testing

Run the test suite:

```bash
swift test
```

All 87 tests pass, covering:
- Context creation and lifecycle
- Script evaluation
- Type conversion (arrays, dictionaries, primitives)
- Object and array access
- Error handling
- Global object access
- Native function binding (16 tests)
- Custom class registration (15 tests)
- Function calling and constructors (19 tests)

## Roadmap

- [x] Core execution engine
- [x] Type conversion
- [x] GC safety
- [x] Error handling
- [x] Native function binding
- [x] Custom class registration
- [ ] Property getters/setters for classes
- [ ] Static methods for classes
- [ ] Comprehensive examples
- [ ] Performance optimizations

## Contributing

Contributions welcome! Areas of interest:

1. Property getters/setters for registered classes
2. Static methods for registered classes
3. Class inheritance support
4. Additional type conversions
5. Performance benchmarks
6. More examples and documentation

## License

SwiftMQuickJS is released under the MIT License. See LICENSE for details.

mquickjs is Copyright (c) 2017-2025 Fabrice Bellard and Charlie Gordon, released under the MIT License.

## Credits

- **mquickjs**: Fabrice Bellard and Charlie Gordon

## Related Projects

- [QuickJS](https://bellard.org/quickjs/) - The full-featured JavaScript engine
- [JavaScriptCore](https://developer.apple.com/documentation/javascriptcore) - Apple's JavaScript engine

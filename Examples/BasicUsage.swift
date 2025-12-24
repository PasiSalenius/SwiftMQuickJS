import Foundation
import MQuickJS

/// Basic examples demonstrating SwiftMQuickJS functionality
class BasicUsageExamples {

    // MARK: - Example 1: Simple Evaluation

    static func simpleEvaluation() throws {
        print("=== Example 1: Simple Evaluation ===")

        let context = try MQJSContext()

        // Basic arithmetic
        let sum = try context.eval("2 + 3")
        print("2 + 3 = \(try sum.toInt32())") // 5

        // String concatenation
        let greeting = try context.eval("'Hello' + ', ' + 'World!'")
        print(try greeting.toString()) // "Hello, World!"

        // Math operations
        let pi = try context.eval("Math.PI")
        print("π = \(try pi.toDouble())") // 3.141592653589793

        print()
    }

    // MARK: - Example 2: Working with Objects

    static func objectManipulation() throws {
        print("=== Example 2: Working with Objects ===")

        let context = try MQJSContext()

        // Create a person object
        let person = try context.eval("""
            ({
                name: 'Alice',
                age: 30,
                city: 'San Francisco',
                hobbies: ['reading', 'coding', 'hiking']
            })
        """)

        // Access properties
        if let name = person["name"] {
            print("Name: \(try name.toString())")
        }

        if let age = person["age"] {
            print("Age: \(try age.toInt32())")
        }

        if let city = person["city"] {
            print("City: \(try city.toString())")
        }

        // Access nested array
        if let hobbies = person["hobbies"] {
            if let firstHobby = hobbies[0] {
                print("First hobby: \(try firstHobby.toString())")
            }

            if let hobbyCount = hobbies["length"] {
                print("Total hobbies: \(try hobbyCount.toInt32())")
            }
        }

        print()
    }

    // MARK: - Example 3: Arrays

    static func arrayOperations() throws {
        print("=== Example 3: Arrays ===")

        let context = try MQJSContext()

        // Create and manipulate arrays
        let numbers = try context.eval("[10, 20, 30, 40, 50]")

        // Access elements
        for i in 0..<5 {
            if let element = numbers[i] {
                print("numbers[\(i)] = \(try element.toInt32())")
            }
        }

        // Array length
        if let length = numbers["length"] {
            print("Array length: \(try length.toInt32())")
        }

        // Complex array operations
        let result = try context.eval("""
            var arr = [1, 2, 3, 4, 5];
            var doubled = arr.map(x => x * 2);
            var sum = doubled.reduce((a, b) => a + b, 0);
            sum
        """)
        print("Sum of doubled array: \(try result.toInt32())") // 30

        print()
    }

    // MARK: - Example 4: Global Variables

    static func globalVariables() throws {
        print("=== Example 4: Global Variables ===")

        let context = try MQJSContext()

        // Set global variables from JavaScript
        try context.eval("var appName = 'SwiftMQuickJS'")
        try context.eval("var version = 1.0")
        try context.eval("var isActive = true")

        // Access through global object
        let global = context.globalObject

        if let appName = global["appName"] {
            print("App Name: \(try appName.toString())")
        }

        if let version = global["version"] {
            print("Version: \(try version.toDouble())")
        }

        if let isActive = global["isActive"] {
            print("Is Active: \(try isActive.toBool())")
        }

        // Set from Swift
        global["swiftValue"] = try 42.toJSValue(in: context)

        let result = try context.eval("swiftValue * 2")
        print("swiftValue * 2 = \(try result.toInt32())") // 84

        print()
    }

    // MARK: - Example 5: Type Conversion

    static func typeConversion() throws {
        print("=== Example 5: Type Conversion ===")

        let context = try MQJSContext()

        // Swift to JavaScript
        let swiftInt = 42
        let swiftDouble = 3.14159
        let swiftString = "Hello from Swift"
        let swiftBool = true

        let jsInt = try swiftInt.toJSValue(in: context)
        let jsDouble = try swiftDouble.toJSValue(in: context)
        let jsString = try swiftString.toJSValue(in: context)
        let jsBool = try swiftBool.toJSValue(in: context)

        print("Converted to JS:")
        print("  Int: \(try jsInt.toInt32())")
        print("  Double: \(try jsDouble.toDouble())")
        print("  String: \(try jsString.toString())")
        print("  Bool: \(try jsBool.toBool())")

        // Arrays
        let swiftArray = [1, 2, 3, 4, 5]
        let jsArray = try swiftArray.toJSValue(in: context)
        print("  Array[2]: \(try jsArray[2]!.toInt32())")

        // Dictionaries
        let swiftDict: [String: Any] = ["name": "Bob", "age": 25]
        let jsObject = try swiftDict.toJSValue(in: context)
        if let name = jsObject["name"] {
            print("  Dict name: \(try name.toString())")
        }

        print()
    }

    // MARK: - Example 6: Error Handling

    static func errorHandling() {
        print("=== Example 6: Error Handling ===")

        let context = try! MQJSContext()

        // Syntax error
        do {
            let _ = try context.eval("function broken(")
        } catch MQJSError.evaluationError(let message) {
            print("Caught syntax error: \(message)")
        } catch {
            print("Unexpected error: \(error)")
        }

        // Runtime error
        do {
            let _ = try context.eval("undefined.foo()")
        } catch MQJSError.evaluationError(let message) {
            print("Caught runtime error: \(message)")
        } catch {
            print("Unexpected error: \(error)")
        }

        // Reference error
        do {
            let _ = try context.eval("nonexistentVariable")
        } catch MQJSError.evaluationError(let message) {
            print("Caught reference error: \(message)")
        } catch {
            print("Unexpected error: \(error)")
        }

        print()
    }

    // MARK: - Example 7: Multiple Contexts

    static func multipleContexts() throws {
        print("=== Example 7: Multiple Contexts ===")

        // Create separate contexts
        let context1 = try MQJSContext()
        let context2 = try MQJSContext()

        // Each has its own global scope
        try context1.eval("var x = 100")
        try context2.eval("var x = 200")

        let x1 = try context1.eval("x")
        let x2 = try context2.eval("x")

        print("Context 1 x: \(try x1.toInt32())") // 100
        print("Context 2 x: \(try x2.toInt32())") // 200

        print()
    }

    // MARK: - Example 8: Date and JSON

    static func dateAndJSON() throws {
        print("=== Example 8: Date and JSON ===")

        let context = try MQJSContext()

        // Date
        let now = try context.eval("Date.now()")
        print("Timestamp: \(try now.toInt32())")

        // JSON operations
        let jsonString = """
        {"name": "Charlie", "scores": [95, 87, 92], "active": true}
        """

        let parsed = try context.eval("""
            JSON.parse('\(jsonString)')
        """)

        if let name = parsed["name"] {
            print("Name from JSON: \(try name.toString())")
        }

        if let scores = parsed["scores"], let firstScore = scores[0] {
            print("First score: \(try firstScore.toInt32())")
        }

        // Stringify
        let stringified = try context.eval("""
            JSON.stringify({ foo: 'bar', num: 42 })
        """)
        print("Stringified: \(try stringified.toString())")

        print()
    }

    // MARK: - Example 9: Memory Management

    static func memoryManagement() throws {
        print("=== Example 9: Memory Management ===")

        // Different memory sizes for different use cases
        let tinyContext = try MQJSContext(
            memorySize: MQJSContext.memoryForSimpleScripts
        )
        print("Tiny context created with 64KB")

        let normalContext = try MQJSContext(
            memorySize: MQJSContext.memoryForModerateScripts
        )
        print("Normal context created with 256KB")

        let largeContext = try MQJSContext(
            memorySize: MQJSContext.memoryForDevelopment
        )
        print("Large context created with 4MB")

        // Contexts automatically clean up when deallocated
        // No manual memory management needed!

        print()
    }

    // MARK: - Example 10: Real-World Use Case

    static func realWorldExample() throws {
        print("=== Example 10: Real-World Use Case ===")
        print("(URL Rewriting)")

        let context = try MQJSContext(
            memorySize: MQJSContext.memoryForModerateScripts
        )

        // Load URL rewriting rules
        try context.eval("""
            var urlRules = {
                'old-domain.com': 'new-domain.com',
                'api.staging.com': 'api.production.com'
            };

            function rewriteURL(url) {
                for (var oldDomain in urlRules) {
                    if (url.includes(oldDomain)) {
                        return url.replace(oldDomain, urlRules[oldDomain]);
                    }
                }
                return url;
            }

            function shouldBlockURL(url) {
                var blocked = ['ads.example.com', 'tracker.com'];
                return blocked.some(domain => url.includes(domain));
            }
        """)

        // Test URL rewriting
        let testURLs = [
            "https://old-domain.com/path",
            "https://api.staging.com/v1/users",
            "https://ads.example.com/banner.jpg",
            "https://safe-domain.com/content"
        ]

        for url in testURLs {
            // Check if blocked
            try context.eval("var __currentURL = '\(url)'")
            let isBlocked = try context.eval("shouldBlockURL(__currentURL)")

            if try isBlocked.toBool() {
                print("❌ BLOCKED: \(url)")
            } else {
                // Rewrite if not blocked
                let rewritten = try context.eval("rewriteURL(__currentURL)")
                let newURL = try rewritten.toString()
                if newURL != url {
                    print("✏️  REWRITTEN: \(url)")
                    print("           → \(newURL)")
                } else {
                    print("✅ ALLOWED: \(url)")
                }
            }
        }

        print()
    }

    // MARK: - Run All Examples

    static func runAll() {
        do {
            try simpleEvaluation()
            try objectManipulation()
            try arrayOperations()
            try globalVariables()
            try typeConversion()
            errorHandling()
            try multipleContexts()
            try dateAndJSON()
            try memoryManagement()
            try realWorldExample()

            print("✅ All examples completed successfully!")
        } catch {
            print("❌ Error running examples: \(error)")
        }
    }
}

// Run if executed directly
if CommandLine.arguments.contains("--run-examples") {
    BasicUsageExamples.runAll()
}

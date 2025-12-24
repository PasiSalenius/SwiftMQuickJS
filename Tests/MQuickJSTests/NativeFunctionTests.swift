import XCTest
@testable import MQuickJS

/// Tests for native function binding (Swift functions callable from JavaScript)
final class NativeFunctionTests: XCTestCase {

    // MARK: - Basic Function Registration

    func testSimpleNativeFunction() throws {
        let context = try MQJSContext()

        try context.setFunction("double") { args in
            let n = try args[0].toInt32()
            return n * 2
        }

        let result = try context.eval("double(21)")
        XCTAssertEqual(try result.toInt32(), 42)
    }

    func testNativeFunctionReturningString() throws {
        let context = try MQJSContext()

        try context.setFunction("greet") { args in
            let name = try args[0].toString()
            return "Hello, \(name)!"
        }

        let result = try context.eval("greet('World')")
        XCTAssertEqual(try result.toString(), "Hello, World!")
    }

    func testNativeFunctionWithMultipleArguments() throws {
        let context = try MQJSContext()

        try context.setFunction("add") { args in
            let a = try args[0].toInt32()
            let b = try args[1].toInt32()
            return a + b
        }

        let result = try context.eval("add(5, 3)")
        XCTAssertEqual(try result.toInt32(), 8)
    }

    func testNativeFunctionReturningBool() throws {
        let context = try MQJSContext()

        try context.setFunction("isEven") { args in
            let n = try args[0].toInt32()
            return n % 2 == 0
        }

        let trueResult = try context.eval("isEven(4)")
        XCTAssertEqual(try trueResult.toBool(), true)

        let falseResult = try context.eval("isEven(5)")
        XCTAssertEqual(try falseResult.toBool(), false)
    }

    func testNativeFunctionReturningDouble() throws {
        let context = try MQJSContext()

        try context.setFunction("half") { args in
            let n = try args[0].toDouble()
            return n / 2.0
        }

        let result = try context.eval("half(7)")
        XCTAssertEqual(try result.toDouble(), 3.5)
    }

    // MARK: - Returning nil/undefined

    func testNativeFunctionReturningNil() throws {
        let context = try MQJSContext()

        try context.setFunction("doNothing") { _ in
            return nil
        }

        let result = try context.eval("doNothing()")
        XCTAssertTrue(result.isUndefined)
    }

    // MARK: - No Arguments

    func testNativeFunctionWithNoArguments() throws {
        let context = try MQJSContext()

        try context.setFunction("getAnswer") { _ in
            return 42
        }

        let result = try context.eval("getAnswer()")
        XCTAssertEqual(try result.toInt32(), 42)
    }

    // MARK: - Returning Complex Types

    func testNativeFunctionReturningArray() throws {
        let context = try MQJSContext()

        try context.setFunction("getNumbers") { _ in
            return [1, 2, 3, 4, 5]
        }

        let result = try context.eval("getNumbers()")
        XCTAssertTrue(result.isObject)

        let length = result["length"]
        XCTAssertEqual(try length?.toInt32(), 5)
        XCTAssertEqual(try result[0]?.toInt32(), 1)
        XCTAssertEqual(try result[4]?.toInt32(), 5)
    }

    func testNativeFunctionReturningDictionary() throws {
        let context = try MQJSContext()

        try context.setFunction("getPerson") { _ in
            return ["name": "Alice", "age": 30] as [String: Any]
        }

        let result = try context.eval("getPerson()")
        XCTAssertTrue(result.isObject)
        XCTAssertEqual(try result["name"]?.toString(), "Alice")
        XCTAssertEqual(try result["age"]?.toInt32(), 30)
    }

    // MARK: - Called From JS Functions

    func testNativeFunctionCalledFromJSFunction() throws {
        let context = try MQJSContext()

        try context.setFunction("square") { args in
            let n = try args[0].toInt32()
            return n * n
        }

        try context.eval("""
            function sumOfSquares(a, b) {
                return square(a) + square(b);
            }
        """)

        let result = try context.eval("sumOfSquares(3, 4)")
        XCTAssertEqual(try result.toInt32(), 25)  // 9 + 16
    }

    // MARK: - Multiple Native Functions

    func testMultipleNativeFunctions() throws {
        let context = try MQJSContext()

        try context.setFunction("add") { args in
            return try args[0].toInt32() + args[1].toInt32()
        }

        try context.setFunction("multiply") { args in
            return try args[0].toInt32() * args[1].toInt32()
        }

        let result = try context.eval("multiply(add(2, 3), 4)")
        XCTAssertEqual(try result.toInt32(), 20)  // (2 + 3) * 4
    }

    // MARK: - Error Handling

    func testNativeFunctionThrowingError() throws {
        let context = try MQJSContext()

        try context.setFunction("willFail") { _ in
            throw MQJSError.evaluationError("Something went wrong")
        }

        XCTAssertThrowsError(try context.eval("willFail()")) { error in
            guard case MQJSError.evaluationError(let message) = error else {
                XCTFail("Expected evaluationError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Something went wrong"))
        }
    }

    // MARK: - Function on Object

    func testNativeFunctionOnObject() throws {
        let context = try MQJSContext()

        let myObj = try context.eval("({ value: 10 })")

        try context.setFunction("getValue", on: myObj) { _ in
            return 42
        }

        // Set myObj on global before calling
        context.globalObject["myObj"] = myObj
        let result = try context.eval("myObj.getValue()")
        XCTAssertEqual(try result.toInt32(), 42)
    }

    // MARK: - Capturing Swift State

    func testNativeFunctionCapturingState() throws {
        let context = try MQJSContext()

        var counter = 0

        try context.setFunction("increment") { _ in
            counter += 1
            return counter
        }

        XCTAssertEqual(try context.eval("increment()").toInt32(), 1)
        XCTAssertEqual(try context.eval("increment()").toInt32(), 2)
        XCTAssertEqual(try context.eval("increment()").toInt32(), 3)
        XCTAssertEqual(counter, 3)
    }

    // MARK: - Receiving Array Arguments

    func testNativeFunctionReceivingArray() throws {
        let context = try MQJSContext()

        try context.setFunction("sum") { args in
            let array = try args[0].toArray()
            var total = 0
            for item in array {
                if let num = item as? Int {
                    total += num
                }
            }
            return total
        }

        let result = try context.eval("sum([1, 2, 3, 4, 5])")
        XCTAssertEqual(try result.toInt32(), 15)
    }

    // MARK: - Receiving Object Arguments

    func testNativeFunctionReceivingObject() throws {
        let context = try MQJSContext()

        try context.setFunction("getFullName") { args in
            let person = args[0]
            let first = try person["firstName"]?.toString() ?? ""
            let last = try person["lastName"]?.toString() ?? ""
            return "\(first) \(last)"
        }

        let result = try context.eval("getFullName({ firstName: 'John', lastName: 'Doe' })")
        XCTAssertEqual(try result.toString(), "John Doe")
    }
}

import XCTest
@testable import MQuickJS

final class BasicTests: XCTestCase {
    func testContextCreation() throws {
        let context = try MQJSContext()
        XCTAssertNotNil(context)
    }

    func testSimpleEval() throws {
        let context = try MQJSContext()
        let result = try context.eval("1 + 2")
        let value = try result.toInt32()
        XCTAssertEqual(value, 3)
    }

    func testStringEval() throws {
        let context = try MQJSContext()
        let result = try context.eval("'Hello, World!'")
        let value = try result.toString()
        XCTAssertEqual(value, "Hello, World!")
    }

    func testObjectCreation() throws {
        let context = try MQJSContext()
        let result = try context.eval("({ name: 'Alice', age: 30 })")

        XCTAssertTrue(result.isObject)

        let name = try result["name"]?.toString()
        XCTAssertEqual(name, "Alice")

        let age = try result["age"]?.toInt32()
        XCTAssertEqual(age, 30)
    }

    func testArrayCreation() throws {
        let context = try MQJSContext()
        let result = try context.eval("[1, 2, 3, 4, 5]")

        XCTAssertTrue(result.isObject)

        let first = try result[0]?.toInt32()
        XCTAssertEqual(first, 1)

        let last = try result[4]?.toInt32()
        XCTAssertEqual(last, 5)
    }

    func testGlobalObject() throws {
        let context = try MQJSContext()

        // Set a global variable
        try context.eval("var myVar = 42")

        // Access it through global object
        let value = try context.globalObject["myVar"]?.toInt32()
        XCTAssertEqual(value, 42)
    }

    func testTypeConversion() throws {
        let context = try MQJSContext()

        // Int conversion
        let intValue = try 42.toJSValue(in: context)
        let backToInt = try Int(from: intValue)
        XCTAssertEqual(backToInt, 42)

        // String conversion
        let strValue = try "Hello".toJSValue(in: context)
        let backToStr = try String(from: strValue)
        XCTAssertEqual(backToStr, "Hello")

        // Bool conversion
        let boolValue = try true.toJSValue(in: context)
        let backToBool = try Bool(from: boolValue)
        XCTAssertEqual(backToBool, true)

        // Double conversion
        let doubleValue = try 3.14.toJSValue(in: context)
        let backToDouble = try Double(from: doubleValue)
        XCTAssertEqual(backToDouble, 3.14, accuracy: 0.001)
    }

    func testArrayConversion() throws {
        let context = try MQJSContext()

        let swiftArray = [1, 2, 3, 4, 5]
        let jsArray = try swiftArray.toJSValue(in: context)

        let firstElement = try jsArray[0]?.toInt32()
        XCTAssertEqual(firstElement, 1)

        let lastElement = try jsArray[4]?.toInt32()
        XCTAssertEqual(lastElement, 5)
    }

    func testDictionaryConversion() throws {
        let context = try MQJSContext()

        let swiftDict = ["name": "Bob", "city": "NYC"]
        let jsObject = try swiftDict.toJSValue(in: context)

        let name = try jsObject["name"]?.toString()
        XCTAssertEqual(name, "Bob")

        let city = try jsObject["city"]?.toString()
        XCTAssertEqual(city, "NYC")
    }

    func testErrorHandling() throws {
        let context = try MQJSContext()

        do {
            _ = try context.eval("invalid javascript syntax {{{")
            XCTFail("Should have thrown an error")
        } catch {
            // Expected to throw
            XCTAssertTrue(error is MQJSError)
        }
    }

    func testFunctionExecution() throws {
        let context = try MQJSContext()

        // Define a function
        try context.eval("""
            function add(a, b) {
                return a + b;
            }
        """)

        // Get the function
        let addFunc = context.globalObject["add"]
        XCTAssertNotNil(addFunc)
        XCTAssertTrue(addFunc?.isFunction ?? false)
    }

    func testMultipleEvals() throws {
        let context = try MQJSContext()

        try context.eval("var counter = 0")
        try context.eval("counter++")
        try context.eval("counter++")

        let result = try context.eval("counter")
        let value = try result.toInt32()
        XCTAssertEqual(value, 2)
    }

    func testTypeChecking() throws {
        let context = try MQJSContext()

        let numValue = try context.eval("42")
        XCTAssertTrue(numValue.isNumber)
        XCTAssertFalse(numValue.isString)
        XCTAssertFalse(numValue.isObject)

        let strValue = try context.eval("'hello'")
        XCTAssertTrue(strValue.isString)
        XCTAssertFalse(strValue.isNumber)

        let objValue = try context.eval("({})")
        XCTAssertTrue(objValue.isObject)
        XCTAssertFalse(objValue.isNumber)

        let nullValue = try context.eval("null")
        XCTAssertTrue(nullValue.isNull)

        let undefinedValue = try context.eval("undefined")
        XCTAssertTrue(undefinedValue.isUndefined)
    }
}

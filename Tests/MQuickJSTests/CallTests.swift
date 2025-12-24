import XCTest
@testable import MQuickJS

/// Tests for function calling functionality (JSC-compatible API)
final class CallTests: XCTestCase {

    // MARK: - Basic Function Calling

    func testCallSimpleFunction() throws {
        let context = try MQJSContext()
        try context.eval("function add(a, b) { return a + b; }")

        let addFunc = context.globalObject["add"]!
        let result = try addFunc.call(withArguments: [5, 3])

        XCTAssertEqual(try result.toInt32(), 8)
    }

    func testCallWithNoArguments() throws {
        let context = try MQJSContext()
        try context.eval("function getAnswer() { return 42; }")

        let result = try context.callFunction("getAnswer")
        XCTAssertEqual(try result.toInt32(), 42)
    }

    func testCallWithNilArguments() throws {
        let context = try MQJSContext()
        try context.eval("function getAnswer() { return 42; }")

        let getAnswer = context.globalObject["getAnswer"]!
        let result = try getAnswer.call(withArguments: nil)
        XCTAssertEqual(try result.toInt32(), 42)
    }

    func testCallWithMixedArgumentTypes() throws {
        let context = try MQJSContext()
        try context.eval("""
            function format(name, age, active) {
                return name + " is " + age + " (" + (active ? "active" : "inactive") + ")";
            }
        """)

        let result = try context.callFunction("format", withArguments: ["Alice", 30, true])
        XCTAssertEqual(try result.toString(), "Alice is 30 (active)")
    }

    func testCallReturnsUndefined() throws {
        let context = try MQJSContext()
        try context.eval("function noReturn() { }")

        let result = try context.callFunction("noReturn")
        XCTAssertTrue(result.isUndefined)
    }

    func testCallReturnsNull() throws {
        let context = try MQJSContext()
        try context.eval("function returnNull() { return null; }")

        let result = try context.callFunction("returnNull")
        XCTAssertTrue(result.isNull)
    }

    // MARK: - Method Invocation

    func testInvokeMethod() throws {
        let context = try MQJSContext()
        try context.eval("""
            var calculator = {
                add: function(a, b) { return a + b; },
                multiply: function(a, b) { return a * b; }
            };
        """)

        let calc = context.globalObject["calculator"]!
        let sum = try calc.invokeMethod("add", withArguments: [5, 3])
        XCTAssertEqual(try sum.toInt32(), 8)

        let product = try calc.invokeMethod("multiply", withArguments: [5, 3])
        XCTAssertEqual(try product.toInt32(), 15)
    }

    func testInvokeMethodWithThis() throws {
        let context = try MQJSContext()
        try context.eval("""
            var obj = {
                value: 100,
                getValue: function() { return this.value; },
                add: function(n) { return this.value + n; }
            };
        """)

        let obj = context.globalObject["obj"]!
        let getValue = try obj.invokeMethod("getValue", withArguments: nil)
        XCTAssertEqual(try getValue.toInt32(), 100)

        let added = try obj.invokeMethod("add", withArguments: [50])
        XCTAssertEqual(try added.toInt32(), 150)
    }

    // MARK: - Constructor Calls

    func testConstructObject() throws {
        let context = try MQJSContext()

        // Note: mquickjs has limited Date support (only Date.now())
        // Test with Object constructor instead
        let ObjectCtor = context.globalObject["Object"]!
        let obj = try ObjectCtor.construct(withArguments: nil)

        XCTAssertTrue(obj.isObject)
        XCTAssertFalse(obj.isNull)
    }

    func testConstructArray() throws {
        let context = try MQJSContext()

        let ArrayCtor = context.globalObject["Array"]!
        let arr = try ArrayCtor.construct(withArguments: [1, 2, 3])

        let length = arr["length"]!
        XCTAssertEqual(try length.toInt32(), 3)
    }

    func testConstructCustomClass() throws {
        let context = try MQJSContext()
        try context.eval("""
            function Person(name, age) {
                this.name = name;
                this.age = age;
            }
            Person.prototype.greet = function() {
                return "Hello, " + this.name;
            };
        """)

        let PersonCtor = context.globalObject["Person"]!
        let person = try PersonCtor.construct(withArguments: ["Alice", 30])

        XCTAssertEqual(try person["name"]?.toString(), "Alice")
        XCTAssertEqual(try person["age"]?.toInt32(), 30)

        let greeting = try person.invokeMethod("greet", withArguments: nil)
        XCTAssertEqual(try greeting.toString(), "Hello, Alice")
    }

    // MARK: - Error Handling

    func testCallNonFunctionThrows() throws {
        let context = try MQJSContext()
        let num = try context.eval("42")

        XCTAssertThrowsError(try num.call(withArguments: nil)) { error in
            guard case MQJSError.notAFunction = error else {
                XCTFail("Expected notAFunction error, got \(error)")
                return
            }
        }
    }

    func testCallThrowsJavaScriptError() throws {
        let context = try MQJSContext()
        try context.eval("""
            function throwError() {
                throw new Error("Test error");
            }
        """)

        XCTAssertThrowsError(try context.callFunction("throwError")) { error in
            guard case MQJSError.evaluationError(let msg) = error else {
                XCTFail("Expected evaluationError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Error"), "Error message should contain 'Error': \(msg)")
        }
    }

    func testInvokeMethodOnNonObject() throws {
        let context = try MQJSContext()
        let num = try context.eval("42")

        XCTAssertThrowsError(try num.invokeMethod("toString", withArguments: nil)) { error in
            guard case MQJSError.notAnObject = error else {
                XCTFail("Expected notAnObject error, got \(error)")
                return
            }
        }
    }

    func testCallNonExistentFunction() throws {
        let context = try MQJSContext()

        // Accessing a non-existent global returns undefined, which is not a function
        XCTAssertThrowsError(try context.callFunction("nonExistent")) { error in
            guard case MQJSError.notAFunction = error else {
                XCTFail("Expected notAFunction error, got \(error)")
                return
            }
        }
    }

    // MARK: - Complex Arguments

    func testCallWithArrayArgument() throws {
        let context = try MQJSContext()
        try context.eval("""
            function sum(arr) {
                return arr.reduce(function(a, b) { return a + b; }, 0);
            }
        """)

        let result = try context.callFunction("sum", withArguments: [[1, 2, 3, 4, 5]])
        XCTAssertEqual(try result.toInt32(), 15)
    }

    func testCallWithDictionaryArgument() throws {
        let context = try MQJSContext()
        try context.eval("""
            function getFullName(person) {
                return person.firstName + " " + person.lastName;
            }
        """)

        let person: [String: Any] = ["firstName": "John", "lastName": "Doe"]
        let result = try context.callFunction("getFullName", withArguments: [person])
        XCTAssertEqual(try result.toString(), "John Doe")
    }

    func testCallWithNestedObjects() throws {
        let context = try MQJSContext()
        try context.eval("""
            function getCity(data) {
                return data.user.address.city;
            }
        """)

        let data: [String: Any] = [
            "user": [
                "name": "Alice",
                "address": [
                    "city": "New York",
                    "zip": "10001"
                ]
            ]
        ]

        let result = try context.callFunction("getCity", withArguments: [data])
        XCTAssertEqual(try result.toString(), "New York")
    }

    // MARK: - Callback Pattern

    func testCallbackPattern() throws {
        let context = try MQJSContext()
        try context.eval("""
            function processItems(items, callback) {
                var results = [];
                for (var i = 0; i < items.length; i++) {
                    results.push(callback(items[i]));
                }
                return results;
            }

            function double(x) {
                return x * 2;
            }
        """)

        let items = [1, 2, 3, 4, 5]
        let doubleFunc = context.globalObject["double"]!
        let result = try context.callFunction("processItems", withArguments: [items, doubleFunc])

        let array = try result.toArray()
        XCTAssertEqual(array.count, 5)
        XCTAssertEqual(array[0] as? Int, 2)
        XCTAssertEqual(array[4] as? Int, 10)
    }
}

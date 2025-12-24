import XCTest
@testable import MQuickJS

/// Tests for type conversion functionality (JSC-compatible API)
final class ConversionTests: XCTestCase {

    // MARK: - toArray()

    func testToArraySimple() throws {
        let context = try MQJSContext()
        let arr = try context.eval("[1, 2, 3, 4, 5]")

        let swiftArray = try arr.toArray()

        XCTAssertEqual(swiftArray.count, 5)
        XCTAssertEqual(swiftArray[0] as? Int, 1)
        XCTAssertEqual(swiftArray[4] as? Int, 5)
    }

    func testToArrayMixedTypes() throws {
        let context = try MQJSContext()
        let arr = try context.eval("[1, 'hello', true, null, 3.14]")

        let swiftArray = try arr.toArray()

        XCTAssertEqual(swiftArray.count, 5)
        XCTAssertEqual(swiftArray[0] as? Int, 1)
        XCTAssertEqual(swiftArray[1] as? String, "hello")
        XCTAssertEqual(swiftArray[2] as? Bool, true)
        XCTAssertTrue(swiftArray[3] is NSNull)
        XCTAssertEqual(swiftArray[4] as? Double, 3.14)
    }

    func testToArrayNested() throws {
        let context = try MQJSContext()
        let arr = try context.eval("[[1, 2], [3, 4], [5, 6]]")

        let swiftArray = try arr.toArray()

        XCTAssertEqual(swiftArray.count, 3)

        if let inner = swiftArray[0] as? [Any] {
            XCTAssertEqual(inner.count, 2)
            XCTAssertEqual(inner[0] as? Int, 1)
        } else {
            XCTFail("Expected nested array")
        }
    }

    func testToArrayEmpty() throws {
        let context = try MQJSContext()
        let arr = try context.eval("[]")

        let swiftArray = try arr.toArray()

        XCTAssertEqual(swiftArray.count, 0)
    }

    // MARK: - toDictionary()

    func testToDictionarySimple() throws {
        let context = try MQJSContext()
        let obj = try context.eval("({name: 'Alice', age: 30})")

        let dict = try obj.toDictionary()

        XCTAssertEqual(dict["name"] as? String, "Alice")
        XCTAssertEqual(dict["age"] as? Int, 30)
    }

    func testToDictionaryNested() throws {
        let context = try MQJSContext()
        let obj = try context.eval("""
            ({
                user: {
                    name: 'Bob',
                    address: {
                        city: 'Seattle',
                        zip: '98101'
                    }
                }
            })
        """)

        let dict = try obj.toDictionary()

        if let user = dict["user"] as? [String: Any],
           let address = user["address"] as? [String: Any] {
            XCTAssertEqual(address["city"] as? String, "Seattle")
        } else {
            XCTFail("Expected nested dictionary structure")
        }
    }

    func testToDictionaryWithArrayValue() throws {
        let context = try MQJSContext()
        let obj = try context.eval("({items: [1, 2, 3], name: 'test'})")

        let dict = try obj.toDictionary()

        XCTAssertEqual(dict["name"] as? String, "test")
        if let items = dict["items"] as? [Any] {
            XCTAssertEqual(items.count, 3)
        } else {
            XCTFail("Expected array in dictionary")
        }
    }

    func testToDictionaryEmpty() throws {
        let context = try MQJSContext()
        let obj = try context.eval("({})")

        let dict = try obj.toDictionary()

        XCTAssertTrue(dict.isEmpty)
    }

    // MARK: - toObject()

    func testToObjectNumber() throws {
        let context = try MQJSContext()

        let intVal = try context.eval("42")
        XCTAssertEqual(try intVal.toObject() as? Int, 42)

        let floatVal = try context.eval("3.14")
        XCTAssertEqual(try floatVal.toObject() as? Double, 3.14)
    }

    func testToObjectString() throws {
        let context = try MQJSContext()
        let str = try context.eval("'hello world'")

        XCTAssertEqual(try str.toObject() as? String, "hello world")
    }

    func testToObjectBoolean() throws {
        let context = try MQJSContext()

        let trueVal = try context.eval("true")
        XCTAssertEqual(try trueVal.toObject() as? Bool, true)

        let falseVal = try context.eval("false")
        XCTAssertEqual(try falseVal.toObject() as? Bool, false)
    }

    func testToObjectNull() throws {
        let context = try MQJSContext()
        let nullVal = try context.eval("null")

        XCTAssertTrue(try nullVal.toObject() is NSNull)
    }

    func testToObjectUndefined() throws {
        let context = try MQJSContext()
        let undefinedVal = try context.eval("undefined")

        XCTAssertTrue(try undefinedVal.toObject() is NSNull)
    }

    func testToObjectArray() throws {
        let context = try MQJSContext()
        let arr = try context.eval("[1, 2, 3]")

        let result = try arr.toObject()
        XCTAssertTrue(result is [Any])

        if let array = result as? [Any] {
            XCTAssertEqual(array.count, 3)
        }
    }

    func testToObjectDictionary() throws {
        let context = try MQJSContext()
        let obj = try context.eval("({x: 1, y: 2})")

        let result = try obj.toObject()
        XCTAssertTrue(result is [String: Any])

        if let dict = result as? [String: Any] {
            XCTAssertEqual(dict["x"] as? Int, 1)
        }
    }

    // MARK: - Round-trip Conversion

    func testRoundTripArray() throws {
        let context = try MQJSContext()

        // Swift -> JS -> Swift
        let original = [1, 2, 3, 4, 5]
        try context.eval("""
            function identity(arr) { return arr; }
        """)

        let result = try context.callFunction("identity", withArguments: [original])
        let converted = try result.toArray()

        XCTAssertEqual(converted.count, original.count)
        for (i, val) in original.enumerated() {
            XCTAssertEqual(converted[i] as? Int, val)
        }
    }

    func testRoundTripDictionary() throws {
        let context = try MQJSContext()

        let original: [String: Any] = [
            "name": "Alice",
            "age": 30,
            "active": true
        ]

        try context.eval("""
            function identity(obj) { return obj; }
        """)

        let result = try context.callFunction("identity", withArguments: [original])
        let converted = try result.toDictionary()

        XCTAssertEqual(converted["name"] as? String, "Alice")
        XCTAssertEqual(converted["age"] as? Int, 30)
        XCTAssertEqual(converted["active"] as? Bool, true)
    }

    func testModifyAndReturn() throws {
        let context = try MQJSContext()

        try context.eval("""
            function addField(obj) {
                obj.modified = true;
                obj.timestamp = 12345;
                return obj;
            }
        """)

        let input: [String: Any] = ["original": "data"]
        let result = try context.callFunction("addField", withArguments: [input])
        let output = try result.toDictionary()

        XCTAssertEqual(output["original"] as? String, "data")
        XCTAssertEqual(output["modified"] as? Bool, true)
        XCTAssertEqual(output["timestamp"] as? Int, 12345)
    }

    // MARK: - Nested Object Modification Pattern

    func testNestedObjectModification() throws {
        let context = try MQJSContext()

        try context.eval("""
            function modifyData(data) {
                data.metadata["X-Custom-Field"] = "injected";
                data.metadata["X-Original-ID"] = data.id;
                return data;
            }
        """)

        let data: [String: Any] = [
            "type": "record",
            "id": "abc-123",
            "metadata": [
                "format": "json",
                "source": "test"
            ]
        ]

        let result = try context.callFunction("modifyData", withArguments: [data])
        let modified = try result.toDictionary()

        XCTAssertEqual(modified["type"] as? String, "record")
        XCTAssertEqual(modified["id"] as? String, "abc-123")

        if let metadata = modified["metadata"] as? [String: Any] {
            XCTAssertEqual(metadata["X-Custom-Field"] as? String, "injected")
            XCTAssertEqual(metadata["X-Original-ID"] as? String, "abc-123")
            XCTAssertEqual(metadata["format"] as? String, "json")
        } else {
            XCTFail("Expected metadata dictionary")
        }
    }

    func testConditionalModification() throws {
        let context = try MQJSContext()

        try context.eval("""
            function modifyRecord(record) {
                if (record.status === 200) {
                    var payload = JSON.parse(record.payload || "{}");
                    payload.processed = true;
                    record.payload = JSON.stringify(payload);
                }
                record.metadata["modified"] = "true";
                return record;
            }
        """)

        let record: [String: Any] = [
            "status": 200,
            "metadata": ["type": "data"],
            "payload": "{\"value\": \"test\"}"
        ]

        let result = try context.callFunction("modifyRecord", withArguments: [record])
        let modified = try result.toDictionary()

        XCTAssertEqual(modified["status"] as? Int, 200)

        if let metadata = modified["metadata"] as? [String: Any] {
            XCTAssertEqual(metadata["modified"] as? String, "true")
        }

        if let payloadString = modified["payload"] as? String {
            XCTAssertTrue(payloadString.contains("processed"))
        }
    }

    // MARK: - Error Cases

    func testToDictionaryOnNonObject() throws {
        let context = try MQJSContext()
        let num = try context.eval("42")

        XCTAssertThrowsError(try num.toDictionary()) { error in
            guard case MQJSError.typeConversionError = error else {
                XCTFail("Expected typeConversionError, got \(error)")
                return
            }
        }
    }

    func testToArrayOnNonArray() throws {
        let context = try MQJSContext()
        let str = try context.eval("'not an array'")

        XCTAssertThrowsError(try str.toArray()) { error in
            guard case MQJSError.typeConversionError = error else {
                XCTFail("Expected typeConversionError, got \(error)")
                return
            }
        }
    }
}

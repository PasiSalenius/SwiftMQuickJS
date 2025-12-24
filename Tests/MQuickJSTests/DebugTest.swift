import XCTest
@testable import MQuickJS

final class DebugTest: XCTestCase {
    func testBasicEval() throws {
        let context = try MQJSContext()

        print("Context created: \(context.ctx)")
        print("Memory buffer base: \(context.memoryBuffer.baseAddress)")
        print("Memory buffer size: \(context.memoryBuffer.size)")
        print("JS_EVAL_RETVAL value: \(JS_EVAL_RETVAL)")

        // Test what eval actually returns
        let result = try context.eval("42")

        print("\nJSValue raw: \(result.jsValue)")
        print("Result isNumber: \(result.isNumber)")
        print("Result isUndefined: \(result.isUndefined)")
        print("Result isNull: \(result.isNull)")
        print("Result isBool: \(result.isBool)")

        if result.isNumber {
            let val = try result.toInt32()
            print("Result value: \(val)")
        }

        // Try a simple addition
        let addResult = try context.eval("1 + 2")
        print("\n1 + 2 result:")
        print("JSValue raw: \(addResult.jsValue)")
        print("isNumber: \(addResult.isNumber)")
        if addResult.isNumber {
            print("value: \(try addResult.toInt32())")
        }
    }

    func testGlobalAccess() throws {
        let context = try MQJSContext()

        // Define a variable
        try context.eval("var x = 100")

        // Try to access global object
        let global = context.globalObject
        print("Global isObject: \(global.isObject)")
        print("Global isUndefined: \(global.isUndefined)")

        // Try to access x
        let xValue = global["x"]
        print("x isNil: \(xValue == nil)")
        if let xValue = xValue {
            print("x isNumber: \(xValue.isNumber)")
            if xValue.isNumber {
                let val = try xValue.toInt32()
                print("x value: \(val)")
            }
        }
    }
}

import XCTest
@testable import MQuickJS

/// Tests for custom class registration (Swift classes exposed to JavaScript)
final class CustomClassTests: XCTestCase {

    // MARK: - Test Helper Classes

    /// Simple counter class for testing
    class Counter {
        var value: Int

        init(start: Int = 0) {
            self.value = start
        }

        func increment() {
            value += 1
        }

        func decrement() {
            value -= 1
        }

        func getValue() -> Int {
            return value
        }

        func add(_ amount: Int) {
            value += amount
        }
    }

    /// Class for testing string operations
    class Greeter {
        var name: String

        init(name: String) {
            self.name = name
        }

        func greet() -> String {
            return "Hello, \(name)!"
        }

        func setName(_ newName: String) {
            self.name = newName
        }

        func getName() -> String {
            return name
        }
    }

    // MARK: - Basic Class Registration

    func testBasicClassRegistration() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c = new Counter(10);
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 10)
    }

    func testConstructorWithDefaultArguments() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c = new Counter();
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 0)
    }

    // MARK: - Method Calls

    func testMethodThatModifiesState() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c = new Counter(5);
            c.increment();
            c.increment();
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 7)
    }

    func testMethodWithArguments() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("add") { this, args in
                let amount = try args[0].toInt32()
                this.add(Int(amount))
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c = new Counter(10);
            c.add(5);
            c.add(3);
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 18)
    }

    func testMethodReturningString() throws {
        let context = try MQJSContext()

        try context.registerClass("Greeter") { (builder: MQJSClassBuilder<Greeter>) in
            builder.constructor { args in
                let name = (try? args.first?.toString()) ?? "World"
                return Greeter(name: name)
            }
            builder.method("greet") { this, _ in
                return this.greet()
            }
        }

        let result = try context.eval("""
            var g = new Greeter("Alice");
            g.greet();
        """)
        XCTAssertEqual(try result.toString(), "Hello, Alice!")
    }

    // MARK: - Multiple Instances

    func testMultipleInstances() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c1 = new Counter(0);
            var c2 = new Counter(100);
            c1.increment();
            c1.increment();
            c2.increment();
            c1.getValue() + c2.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 103)  // 2 + 101
    }

    func testInstancesAreIndependent() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        // Increment c1 many times, c2 should be unaffected
        let result = try context.eval("""
            var c1 = new Counter(0);
            var c2 = new Counter(0);
            for (var i = 0; i < 10; i++) {
                c1.increment();
            }
            c2.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 0)
    }

    // MARK: - Multiple Methods

    func testMultipleMethods() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("decrement") { this, _ in
                this.decrement()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var c = new Counter(10);
            c.increment();
            c.increment();
            c.decrement();
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 11)
    }

    // MARK: - Instance Stored in JS Variable

    func testInstanceStoredInVariable() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        try context.eval("var globalCounter = new Counter(42);")
        let result = try context.eval("globalCounter.getValue();")
        XCTAssertEqual(try result.toInt32(), 42)
    }

    // MARK: - Instance Passed to JS Function

    func testInstancePassedToJSFunction() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            function incrementTwice(counter) {
                counter.increment();
                counter.increment();
            }
            var c = new Counter(5);
            incrementTwice(c);
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 7)
    }

    // MARK: - Instance in Array

    func testInstancesInArray() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        let result = try context.eval("""
            var counters = [new Counter(1), new Counter(2), new Counter(3)];
            counters[0].getValue() + counters[1].getValue() + counters[2].getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 6)
    }

    // MARK: - Error Handling

    func testMissingConstructor() throws {
        let context = try MQJSContext()

        XCTAssertThrowsError(try context.registerClass("Empty") { (_: MQJSClassBuilder<Counter>) in
            // No constructor defined
        }) { error in
            guard case MQJSError.classRegistrationError(let message) = error else {
                XCTFail("Expected classRegistrationError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Constructor not defined"))
        }
    }

    // MARK: - Multiple Classes

    func testMultipleClasses() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        try context.registerClass("Greeter") { (builder: MQJSClassBuilder<Greeter>) in
            builder.constructor { args in
                let name = (try? args.first?.toString()) ?? "World"
                return Greeter(name: name)
            }
            builder.method("greet") { this, _ in
                return this.greet()
            }
        }

        let counterResult = try context.eval("new Counter(42).getValue();")
        XCTAssertEqual(try counterResult.toInt32(), 42)

        let greeterResult = try context.eval("new Greeter('Bob').greet();")
        XCTAssertEqual(try greeterResult.toString(), "Hello, Bob!")
    }

    // MARK: - Chaining Methods

    func testChainingMethodCalls() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("increment") { this, _ in
                this.increment()
                return nil
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        // Can't chain because increment returns nil/undefined
        // But we can call methods in sequence
        let result = try context.eval("""
            var c = new Counter(0);
            c.increment();
            c.increment();
            c.increment();
            c.getValue();
        """)
        XCTAssertEqual(try result.toInt32(), 3)
    }

    // MARK: - Interaction with Native Functions

    func testClassWithNativeFunction() throws {
        let context = try MQJSContext()

        try context.registerClass("Counter") { (builder: MQJSClassBuilder<Counter>) in
            builder.constructor { args in
                let start = (try? args.first?.toInt32()) ?? 0
                return Counter(start: Int(start))
            }
            builder.method("getValue") { this, _ in
                return this.getValue()
            }
        }

        try context.setFunction("double") { args in
            let n = try args[0].toInt32()
            return n * 2
        }

        let result = try context.eval("""
            var c = new Counter(21);
            double(c.getValue());
        """)
        XCTAssertEqual(try result.toInt32(), 42)
    }
}

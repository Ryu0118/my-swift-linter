@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct HoistRepeatedInstanceRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "hoist-repeated-instance"))
    }

    // MARK: - V: Violations

    @Test("bare construction with no configuration, used twice, is a violation")
    func v1_bareNoConfig() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("identical single-property configuration in two functions is a violation")
    func v2_identicalSingleProperty() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("identical multi-property configuration in the same order is a violation")
    func v3_identicalMultiPropertySameOrder() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.keyDecodingStrategy = .convertFromSnakeCase
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.keyDecodingStrategy = .convertFromSnakeCase
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("identical multi-property configuration in different order is still a violation")
    func v4_identicalMultiPropertyDifferentOrder() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.keyDecodingStrategy = .convertFromSnakeCase
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.keyDecodingStrategy = .convertFromSnakeCase
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("three occurrences where only two are identical flags only the identical pair")
    func v5_threeOccurrencesTwoIdentical() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
            func c(_ data: Data) throws -> C {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .secondsSince1970
                return try d.decode(C.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("same identical construction in two branches of one function is a violation")
    func v6_sameFunctionTwoBranches() async {
        let source = """
        struct Foo {
            func decode(_ data: Data, flag: Bool) throws -> Bar {
                if flag {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(Bar.self, from: data)
                } else {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(Bar.self, from: data)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("occurrences split across a type and a same-file extension of it are a violation")
    func v7_typeAndSameFileExtension() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
        }
        extension Foo {
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("occurrences in init and a regular function are a violation")
    func v8_initAndFunction() async {
        let source = """
        struct Foo {
            init(data: Data) throws {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                self.bar = try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
            var bar: Bar
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("occurrences in a computed property getter and a subscript are a violation")
    func v9_computedPropertyAndSubscript() async {
        let source = """
        struct Foo {
            var formatted: String {
                let d = DateFormatter()
                d.dateStyle = .short
                return d.string(from: Date())
            }
            subscript(index: Int) -> String {
                let d = DateFormatter()
                d.dateStyle = .short
                return d.string(from: dates[index])
            }
            var dates: [Date] = []
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("init form JSONDecoder.init() normalizes the same as JSONDecoder()")
    func v10_explicitInitForm() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder.init()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d: JSONDecoder = .init()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("different local variable names for the same type are still matched")
    func v11_differentVariableNames() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let myJSONDecoder = JSONDecoder()
                myJSONDecoder.dateDecodingStrategy = .iso8601
                return try myJSONDecoder.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("type-rooted RHS (e.g. enum case on the assigned type) is hoistable and matched")
    func v12_typeRootedRHS() async {
        let source = """
        struct Foo {
            func a() -> String {
                let f = DateFormatter()
                f.dateStyle = DateFormatter.Style.medium
                return f.string(from: Date())
            }
            func b() -> String {
                let f = DateFormatter()
                f.dateStyle = DateFormatter.Style.medium
                return f.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("var instead of let for the local declaration is still matched")
    func v13_varDeclaration() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> Bar {
                var d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func b(_ data: Data) throws -> Baz {
                var d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("subscript-path assignment on the local variable is still matched")
    func v14_subscriptPathAssignment() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.userInfo[.key] = "v"
                return try d.decode(Bar.self, from: data)
            }
            func b(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.userInfo[.key] = "v"
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("class container is flagged the same as struct")
    func v15_classContainer() async {
        let source = """
        final class Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("actor container is flagged the same as struct")
    func v16_actorContainer() async {
        let source = """
        actor Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("nested type only matches within its own container, not the outer type")
    func v17_nestedType() async {
        let source = """
        struct Outer {
            struct Inner {
                func a(_ data: Data) throws -> Bar {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(Bar.self, from: data)
                }
                func b(_ data: Data) throws -> Baz {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(Baz.self, from: data)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("multiple call-site uses of the base after configuration are still matched")
    func v18_multipleUsesAfterConfig() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                let bar = try d.decode(Bar.self, from: data)
                return try d.decode(Bar.self, from: data)
            }
            func b(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("occurrence inside an inline closure is still matched")
    func v19_insideInlineClosure() async {
        let source = """
        struct Foo {
            func a(_ items: [Data]) -> [Bar?] {
                items.map { data in
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try? d.decode(Bar.self, from: data)
                }
            }
            func b(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("threshold raised via YAML requires more occurrences before flagging")
    func v20_minimumOccurrencesConfigured() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
            func c(_ data: Data) throws -> C {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(C.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "minimum_occurrences: 3\n")
        #expect(diagnostics.count == 3)
    }

    @Test("two independent groups in one container both report, without bleeding into each other")
    func v21_twoIndependentGroups() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
            func b(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
            func c() -> String {
                let f = DateFormatter()
                f.dateStyle = .short
                return f.string(from: Date())
            }
            func e() -> String {
                let f = DateFormatter()
                f.dateStyle = .short
                return f.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 4)
        #expect(diagnostics.map(\.line) == diagnostics.map(\.line).sorted())
    }

    // MARK: - F: False positives (must all be diagnostics.isEmpty)

    @Test("the recommended fix itself — closure-initialized stored property — is not flagged")
    func f1_recommendedFixIsNotFlagged() async {
        let source = """
        struct Foo {
            private let jsonDecoder: JSONDecoder = {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return d
            }()

            static let shared = Foo()

            private lazy var lazyDecoder: JSONDecoder = {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return d
            }()

            func decode(_ data: Data) throws -> Bar {
                try jsonDecoder.decode(Bar.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("different configuration values are not merged as identical")
    func f2_differentConfigValues() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .secondsSince1970
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("partial overlap in configured properties is not flagged")
    func f3_partialOverlap() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.keyDecodingStrategy = .convertFromSnakeCase
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS referencing a function parameter is not flagged")
    func f4_rhsReferencesParameter() async {
        let source = """
        struct Foo {
            func a(_ data: Data, locale: Locale) throws -> A {
                let d = DateFormatter()
                d.locale = locale
                return try d.string(from: Date())
            }
            func b(_ data: Data, locale: Locale) throws -> B {
                let d = DateFormatter()
                d.locale = locale
                return try d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS referencing a local let is not flagged")
    func f5_rhsReferencesLocal() async {
        let source = """
        struct Foo {
            func a() -> String {
                let l = Locale.current
                let d = DateFormatter()
                d.locale = l
                return d.string(from: Date())
            }
            func b() -> String {
                let l = Locale.current
                let d = DateFormatter()
                d.locale = l
                return d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("a local from an outer block still disqualifies an RHS reference inside a nested block")
    func f5b_outerScopeLocalDisqualifiesNestedReference() async {
        let source = """
        struct Foo {
            func a(_ flag: Bool) -> String {
                let l = Locale.current
                if flag {
                    let d = DateFormatter()
                    d.locale = l
                    return d.string(from: Date())
                }
                return ""
            }
            func b(_ flag: Bool) -> String {
                let l = Locale.current
                if flag {
                    let d = DateFormatter()
                    d.locale = l
                    return d.string(from: Date())
                }
                return ""
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS referencing self is not flagged")
    func f6_rhsReferencesSelf() async {
        let source = """
        struct Foo {
            var context: [String: Any] = [:]
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.userInfo[.key] = self.context
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.userInfo[.key] = self.context
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS referencing a bare instance property declared in the same file is not flagged")
    func f7_rhsReferencesInstanceProperty() async {
        let source = """
        struct Foo {
            let currentLocale: Locale = .current
            func a() -> String {
                let d = DateFormatter()
                d.locale = currentLocale
                return d.string(from: Date())
            }
            func b() -> String {
                let d = DateFormatter()
                d.locale = currentLocale
                return d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS calling a bare instance method declared in the same file is not flagged")
    func f7b_rhsCallsInstanceMethod() async {
        let source = """
        struct Foo {
            func makeLocale() -> Locale { .current }
            func a() -> String {
                let d = DateFormatter()
                d.locale = makeLocale()
                return d.string(from: Date())
            }
            func b() -> String {
                let d = DateFormatter()
                d.locale = makeLocale()
                return d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("RHS referencing a closure parameter is not flagged")
    func f8_rhsReferencesClosureParameter() async {
        let source = """
        struct Foo {
            func a(_ locales: [Locale]) -> [String] {
                locales.map { locale in
                    let d = DateFormatter()
                    d.locale = locale
                    return d.string(from: Date())
                }
            }
            func b(_ locales: [Locale]) -> [String] {
                locales.map { locale in
                    let d = DateFormatter()
                    d.locale = locale
                    return d.string(from: Date())
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("configuration guarded by a conditional is not treated as part of the prefix")
    func f9_configurationBehindConditional() async {
        let source = """
        struct Foo {
            func a(_ data: Data, flag: Bool) throws -> A {
                let d = JSONDecoder()
                if flag {
                    d.dateDecodingStrategy = .iso8601
                }
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data, flag: Bool) throws -> B {
                let d = JSONDecoder()
                if flag {
                    d.dateDecodingStrategy = .iso8601
                }
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("configuration interleaved with unrelated statements is not treated as a matching prefix")
    func f10_interleavedConfiguration() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                log("decoding")
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                log("decoding")
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
            func log(_ s: String) {}
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("returning the local variable itself disqualifies it from matching")
    func f11_returnsLocalVariable() async {
        let source = """
        struct Foo {
            func a() -> JSONDecoder {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return d
            }
            func b() -> JSONDecoder {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return d
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("passing the local variable as a bare argument disqualifies it from matching")
    func f12_passedAsBareArgument() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try process(d, data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try process(d, data)
            }
            func process(_ d: JSONDecoder, _ data: Data) throws -> A { fatalError() }
            func process(_ d: JSONDecoder, _ data: Data) throws -> B { fatalError() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("aliasing the local variable to another binding disqualifies it from matching")
    func f13_aliasedToAnotherBinding() async {
        let source = """
        struct Foo {
            var cached: JSONDecoder?
            func a() {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                self.cached = d
            }
            func b() {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                self.cached = d
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("capturing the local variable in a nested closure disqualifies it from matching")
    func f14_capturedInNestedClosure() async {
        let source = """
        struct Foo {
            func a(_ data: Data, completion: @escaping (Bar?) -> Void) {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                Task {
                    completion(try? d.decode(Bar.self, from: data))
                }
            }
            func b(_ data: Data, completion: @escaping (Baz?) -> Void) {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                Task {
                    completion(try? d.decode(Baz.self, from: data))
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("reassigning the local variable disqualifies it from matching")
    func f15_reassigned() async {
        let source = """
        struct Foo {
            func a(_ data: Data, flag: Bool) throws -> A {
                var d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                if flag {
                    d = JSONDecoder()
                }
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data, flag: Bool) throws -> B {
                var d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                if flag {
                    d = JSONDecoder()
                }
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("duplicate assignment to the same property in the prefix disqualifies the occurrence")
    func f16_duplicateAssignmentToSameProperty() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.dateDecodingStrategy = .secondsSince1970
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                d.dateDecodingStrategy = .secondsSince1970
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("compound assignment on the local variable disqualifies it from matching")
    func f17_compoundAssignment() async {
        let source = """
        struct Foo {
            func a() -> String {
                let f = NumberFormatter()
                f.minimumFractionDigits = 2
                f.maximumFractionDigits += 1
                return f.string(from: 1) ?? ""
            }
            func b() -> String {
                let f = NumberFormatter()
                f.minimumFractionDigits = 2
                f.maximumFractionDigits += 1
                return f.string(from: 1) ?? ""
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("types outside the allowlist are not flagged")
    func f18_typeOutsideAllowlist() async {
        let source = """
        struct Foo {
            func a() -> UUID {
                let x = UUID()
                return x
            }
            func b() -> UUID {
                let x = UUID()
                return x
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("initializers with arguments are not flagged")
    func f19_initializerWithArguments() async {
        let source = """
        struct Foo {
            func a() -> String {
                let l = Locale(identifier: "en_US_POSIX")
                return l.identifier
            }
            func b() -> String {
                let l = Locale(identifier: "en_US_POSIX")
                return l.identifier
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("multi-binding declarations are skipped")
    func f20_multiBindingDeclaration() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let e = JSONEncoder(), d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let e = JSONEncoder(), d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("top-level functions outside any container are not flagged")
    func f21_topLevelFunctions() async {
        let source = """
        func a(_ data: Data) throws -> A {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return try d.decode(A.self, from: data)
        }
        func b(_ data: Data) throws -> B {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return try d.decode(B.self, from: data)
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("extension of a type not declared in this file is not flagged")
    func f22_extensionOfExternalType() async {
        let source = """
        extension SomeExternalType {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("protocol extension is not flagged since it cannot hold a stored property")
    func f23_protocolExtension() async {
        let source = """
        protocol P {}
        extension P {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("a nested enum's instance methods are not attributed to the outer struct")
    func f23b_nestedEnumNotAttributedToOuterStruct() async {
        let source = """
        struct Outer {
            enum Inner {
                func a(_ data: Data) throws -> A {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(A.self, from: data)
                }
                func b(_ data: Data) throws -> B {
                    let d = JSONDecoder()
                    d.dateDecodingStrategy = .iso8601
                    return try d.decode(B.self, from: data)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("a top-level enum's instance methods are not flagged since enums cannot hold stored properties")
    func f23c_topLevelEnumNotFlagged() async {
        let source = """
        enum Namespace {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("a single occurrence is below the default minimum and is not flagged")
    func f24_singleOccurrenceBelowThreshold() async {
        let source = """
        struct Foo {
            private let existingDecoder = JSONDecoder()
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("different containers are not merged into the same group")
    func f25_differentContainers() async {
        let source = """
        struct A {
            func a(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Bar.self, from: data)
            }
        }
        struct B {
            func b(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("static functions are out of scope in v1 and are not flagged")
    func f26_staticFunctionsOutOfScope() async {
        let source = """
        struct Foo {
            static func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            static func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("static computed properties are out of scope in v1 and are not flagged")
    func f26b_staticComputedPropertiesOutOfScope() async {
        let source = """
        struct Foo {
            static var a: String {
                let f = DateFormatter()
                f.dateStyle = .short
                return f.string(from: Date())
            }
            static var b: String {
                let f = DateFormatter()
                f.dateStyle = .short
                return f.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("YAML types override replaces the default allowlist")
    func f27_yamlTypesOverrideReplacesDefault() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "types:\n  - JSONEncoder\n")
        #expect(diagnostics.isEmpty)
    }

    @Test("flag_unconfigured false suppresses bare construction violations")
    func f28_flagUnconfiguredFalse() async {
        let source = """
        struct Foo {
            func decode(_ data: Data) throws -> Bar {
                let d = JSONDecoder()
                return try d.decode(Bar.self, from: data)
            }
            func decodeOther(_ data: Data) throws -> Baz {
                let d = JSONDecoder()
                return try d.decode(Baz.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "flag_unconfigured: false\n")
        #expect(diagnostics.isEmpty)
    }

    @Test("minimum_occurrences raised above the actual occurrence count suppresses the violation")
    func f29_minimumOccurrencesRaised() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "minimum_occurrences: 3\n")
        #expect(diagnostics.isEmpty)
    }

    // MARK: - E: Edge cases

    @Test("RHS referencing an unresolvable bare name is still flagged as a residual false-positive class")
    func e1_unresolvableBareNameIsFlagged() async {
        let source = """
        struct Foo {
            func a() -> String {
                let d = DateFormatter()
                d.locale = appLocale
                return d.string(from: Date())
            }
            func b() -> String {
                let d = DateFormatter()
                d.locale = appLocale
                return d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("using the base only to read a property after configuration is still matched")
    func e3_readOnlyUseAfterConfig() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                let strategy = d.dateDecodingStrategy
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                let strategy = d.dateDecodingStrategy
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    @Test("optional-binding pattern name used in RHS disqualifies the occurrence")
    func e5_optionalBindingNameInRHS() async {
        let source = """
        struct Foo {
            func a(_ maybeLocale: Locale?) -> String {
                guard let locale = maybeLocale else { return "" }
                let d = DateFormatter()
                d.locale = locale
                return d.string(from: Date())
            }
            func b(_ maybeLocale: Locale?) -> String {
                guard let locale = maybeLocale else { return "" }
                let d = DateFormatter()
                d.locale = locale
                return d.string(from: Date())
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("an unused local declaration after configuration is still matched")
    func e9_unusedLocalIsStillMatched() async {
        let source = """
        struct Foo {
            func a() {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
            }
            func b() {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
    }

    // MARK: - Message content

    @Test("bare construction message suggests a plain stored property")
    func messageContentBare() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics[0].message.contains("private let"))
        #expect(diagnostics[0].message.contains("JSONDecoder"))
        #expect(diagnostics[0].message.contains("jsonDecoder"))
    }

    @Test("configured construction message suggests a closure-initialized stored property")
    func messageContentConfigured() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.count == 2)
        #expect(diagnostics[0].message.contains("return"))
    }

    // MARK: - YAML severity override

    @Test("default severity is error")
    func defaultSeverityIsError() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("YAML severity override lowers to warning")
    func yamlSeverityOverride() async {
        let source = """
        struct Foo {
            func a(_ data: Data) throws -> A {
                let d = JSONDecoder()
                return try d.decode(A.self, from: data)
            }
            func b(_ data: Data) throws -> B {
                let d = JSONDecoder()
                return try d.decode(B.self, from: data)
            }
        }
        """
        let diagnostics = await rule.lint(source: source, argsYAML: "severity: warning\n")
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test("empty file produces no diagnostics")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }
}

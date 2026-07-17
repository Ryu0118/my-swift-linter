@testable import Rules
import SwiftASTLint
import SwiftASTLintTestSupport
import Testing

struct SwiftUIViewPropertyRuleTests {
    private let rule: any RuleProtocol

    init() throws {
        rule = try #require(rules.find(id: "swiftui-view-property"))
    }

    // MARK: - Pattern A: return is forbidden

    @Test("error when return is used in some View var without @ViewBuilder")
    func returnWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            private var content: some View {
                let x = 42
                return Text("\\(x)")
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when return is used in some View var with @ViewBuilder")
    func returnWithViewBuilder() async {
        let source = """
        struct MyView: View {
            @ViewBuilder
            private var content: some View {
                return Text("hello")
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Pattern B: @ViewBuilder required

    @Test("error when top-level let without @ViewBuilder in some View var")
    func topLevelLetWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            private var overlay: some View {
                let x = 10.0
                let y = 20.0
                return Text("\\(x), \\(y)")
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when top-level var without @ViewBuilder in some View var")
    func topLevelVarWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            private var label: some View {
                var text = "hello"
                text += " world"
                return Text(text)
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when top-level if without @ViewBuilder in some View var")
    func topLevelIfWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            let isLoading: Bool
            private var content: some View {
                if isLoading {
                    ProgressView()
                } else {
                    Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when top-level switch without @ViewBuilder in some View var")
    func topLevelSwitchWithoutViewBuilder() async {
        let source = """
        enum State { case loading, done }
        struct MyView: View {
            let state: State
            private var content: some View {
                switch state {
                case .loading: ProgressView()
                case .done: Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Non-violations

    @Test("no error when top-level View is returned directly without return keyword")
    func directViewNoReturn() async {
        let source = """
        struct MyView: View {
            private var content: some View {
                Group {
                    Text("hello")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @ViewBuilder with top-level let and no return")
    func viewBuilderWithLetNoReturn() async {
        let source = """
        struct MyView: View {
            @ViewBuilder
            private var overlay: some View {
                let x = 10.0
                Text("\\(x)")
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @ViewBuilder with top-level if and no return")
    func viewBuilderWithIfNoReturn() async {
        let source = """
        struct MyView: View {
            let isLoading: Bool
            @ViewBuilder
            private var content: some View {
                if isLoading {
                    ProgressView()
                } else {
                    Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @ViewBuilder with top-level switch and no return")
    func viewBuilderWithSwitchNoReturn() async {
        let source = """
        enum State { case loading, done }
        struct MyView: View {
            let state: State
            @ViewBuilder
            private var content: some View {
                switch state {
                case .loading: ProgressView()
                case .done: Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for non-View computed property using return")
    func nonViewPropertyWithReturn() async {
        let source = """
        struct MyView: View {
            private var title: String {
                let base = "hello"
                return base + " world"
            }
            var body: some View { Text(title) }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for body with top-level if — View.body has implicit @ViewBuilder")
    func bodyWithIf() async {
        let source = """
        struct MyView: View {
            let isLoading: Bool
            var body: some View {
                if isLoading {
                    ProgressView()
                } else {
                    Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for body with top-level switch — View.body has implicit @ViewBuilder")
    func bodyWithSwitch() async {
        let source = """
        enum State { case loading, done }
        struct MyView: View {
            let state: State
            var body: some View {
                switch state {
                case .loading: ProgressView()
                case .done: Text("done")
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for empty file")
    func emptyFile() async {
        let diagnostics = await rule.lint(source: "")
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for let-only top-level when @ViewBuilder present and no return")
    func viewBuilderNoReturn() async {
        let source = """
        struct MyView: View {
            @ViewBuilder
            private var content: some View {
                let zoom = 1.0
                Text("zoom: \\(zoom)")
                Text("second line")
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("fix preserves earlier multibyte line comments when adding ViewBuilder")
    func fixPreservesEarlierMultibyteLineComment() throws {
        let source = """
        struct ShareImageView: View {
            static let imageSize = CGSize(width: 1080, height: 1240) // 画像の最適サイズ（4:5）

            private var content: some View {
                let title = "hello"
                Text(title)
            }
        }
        """
        let (diagnostics, fixedSource) = rule.lintAndFix(source: source)
        let fixed = try #require(fixedSource)

        #expect(diagnostics.contains { $0.isFixable })
        #expect(fixed.contains("static let imageSize = CGSize(width: 1080, height: 1240) // 画像の最適サイズ（4:5）"))
        #expect(fixed.contains("@ViewBuilder\n    private var content: some View"))
        #expect(!fixed.contains("private @ViewBuilder var"))
        #expect(!fixed.contains("height: 12画像"))
    }
}

// Tests for `some View`-returning functions (split into an extension to keep each
// type body within the type_body_length limit).
extension SwiftUIViewPropertyRuleTests {

    // MARK: - Function: Pattern A (return forbidden)

    @Test("error when return is used in some View func without @ViewBuilder")
    func functionReturnWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            private func content(_ flag: Bool) -> some View {
                let x = 42
                return Text("\\(x)")
            }
            var body: some View { content(true) }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when return is used in some View func with @ViewBuilder")
    func functionReturnWithViewBuilder() async {
        let source = """
        struct MyView: View {
            @ViewBuilder
            private func content() -> some View {
                return Text("hello")
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Function: Pattern B (@ViewBuilder required)

    @Test("error when top-level let in some View func without @ViewBuilder")
    func functionTopLevelLetWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            private func label() -> some View {
                let text = "hello"
                return Text(text)
            }
            var body: some View { label() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when top-level if in some View func without @ViewBuilder")
    func functionTopLevelIfWithoutViewBuilder() async {
        let source = """
        struct MyView: View {
            let isLoading: Bool
            private func content() -> some View {
                if isLoading {
                    ProgressView()
                } else {
                    Text("done")
                }
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    @Test("error when top-level switch in some View func without @ViewBuilder")
    func functionTopLevelSwitchWithoutViewBuilder() async {
        let source = """
        enum State { case loading, done }
        struct MyView: View {
            let state: State
            private func content() -> some View {
                switch state {
                case .loading: ProgressView()
                case .done: Text("done")
                }
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Function: Non-violations

    @Test("no error when some View func returns single view with no return keyword")
    func functionDirectViewNoReturn() async {
        let source = """
        struct MyView: View {
            private func content() -> some View {
                Text("hello")
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @ViewBuilder func uses top-level if without return")
    func functionViewBuilderWithIfNoReturn() async {
        let source = """
        struct MyView: View {
            let isLoading: Bool
            @ViewBuilder
            private func content() -> some View {
                if isLoading {
                    ProgressView()
                } else {
                    Text("done")
                }
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error when @ViewBuilder func uses top-level switch without return")
    func functionViewBuilderWithSwitchNoReturn() async {
        let source = """
        enum State { case loading, done }
        struct MyView: View {
            let state: State
            @ViewBuilder
            private func content() -> some View {
                switch state {
                case .loading: ProgressView()
                case .done: Text("done")
                }
            }
            var body: some View { content() }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for non-View function using return")
    func nonViewFunctionWithReturn() async {
        let source = """
        struct MyView: View {
            private func title() -> String {
                let base = "hello"
                return base + " world"
            }
            var body: some View { Text(title()) }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Function: Fix-It output must be syntactically valid

    @Test("fix inserts @ViewBuilder before private modifier, not between it and func")
    func fixPlacesViewBuilderBeforePrivateModifierOnFunction() throws {
        let source = """
        struct MyView: View {
            private func content(for step: Int) -> some View {
                let isActive = step == 1
                Text("\\(isActive)")
            }
            var body: some View { content(for: 1) }
        }
        """
        let (diagnostics, fixedSource) = rule.lintAndFix(source: source)
        let fixed = try #require(fixedSource)

        #expect(diagnostics.contains { $0.isFixable })
        #expect(!fixed.contains("private @ViewBuilder func"))
        #expect(fixed.contains("@ViewBuilder\n    private func content"))
    }
}

// ViewModifier.body(content:) carries an implicit @ViewBuilder from the protocol,
// so the rule must not flag top-level if/switch in it (mirrors the View.body exclusion).
extension SwiftUIViewPropertyRuleTests {
    @Test("no error for ViewModifier.body(content:) with top-level if — implicit @ViewBuilder")
    func viewModifierBodyWithIf() async {
        let source = """
        struct FooModifier: ViewModifier {
            let isActive: Bool

            func body(content: Content) -> some View {
                if isActive {
                    content.opacity(1)
                } else {
                    content
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }

    @Test("no error for ViewModifier.body(content:) with top-level switch — implicit @ViewBuilder")
    func viewModifierBodyWithSwitch() async {
        let source = """
        struct BarModifier: ViewModifier {
            let level: Int

            func body(content: Content) -> some View {
                switch level {
                case 0:
                    content
                default:
                    content.opacity(0.5)
                }
            }
        }
        """
        let diagnostics = await rule.lint(source: source)
        #expect(diagnostics.isEmpty)
    }
}

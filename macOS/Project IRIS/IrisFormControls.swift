import SwiftUI

private struct IrisControlAccentKey: EnvironmentKey { static let defaultValue = IrisDesign.blue }
extension EnvironmentValues {
    var irisControlAccent: Color {
        get { self[IrisControlAccentKey.self] }
        set { self[IrisControlAccentKey.self] = newValue }
    }
}

/// Native text editing with Iris's shared input surface, including secure fields.
struct IrisTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.irisControlAccent) private var accent
    @Environment(\.irisReduceMotion) private var reduceMotion
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain)
            .font(.system(size: 14)).foregroundStyle(IrisDesign.text)
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(minHeight: 44, alignment: .leading)
            .background(LinearGradient(colors: [IrisDesign.control.opacity(focused ? 0.85 : 0.65), IrisDesign.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? accent.opacity(0.9) : .white.opacity(hovered ? 0.23 : 0.11), lineWidth: focused ? 1.5 : 1) }
            .focused($focused).onHover { hovered = $0 }
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
    }
}

/// Persistent labels keep personal details understandable after the placeholder disappears.
struct IrisFormField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var symbol: String? = nil
    var multiline = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).irisSymbolStyle().accessibilityHidden(true) }
                Text(title)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.secondary)
            TextField(title, text: $text, prompt: Text(prompt), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...5 : 1...1).textFieldStyle(IrisTextFieldStyle()).accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Typed choices are rendered by Iris rather than by the macOS menu system.
struct IrisPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var id: Value { value }
}

struct IrisPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    var display: String? = nil
    var showsTitle = true
    var footerTitle: String? = nil
    var footerAction: (() -> Void)? = nil
    let options: [IrisPickerOption<Value>]
    @State private var hovered = false
    @State private var expanded = false
    @State private var width: CGFloat = 280
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.irisControlAccent) private var accent
    @Environment(\.irisReduceMotion) private var reduceMotion
    init(_ title: String, selection: Binding<Value>, display: String? = nil, showsTitle: Bool = true, footerTitle: String? = nil, footerAction: (() -> Void)? = nil, options: [IrisPickerOption<Value>]) {
        self.title = title; self._selection = selection; self.display = display; self.showsTitle = showsTitle
        self.footerTitle = footerTitle; self.footerAction = footerAction; self.options = options
    }
    private var valueLabel: String { display ?? options.first(where: { $0.value == selection })?.title ?? "Choose…" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsTitle { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.secondary) }
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    Text(valueLabel).font(.system(size: 14, weight: .medium)).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").irisSymbolStyle().font(.system(size: 10, weight: .semibold)).foregroundStyle(accent).rotationEffect(.degrees(expanded ? 180 : 0)).accessibilityHidden(true)
                }.foregroundStyle(IrisDesign.text).padding(.horizontal, 14).padding(.vertical, 13).frame(minHeight: 44)
                    .background(LinearGradient(colors: [IrisDesign.control.opacity(hovered || expanded ? 0.95 : 0.7), IrisDesign.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(focused || expanded ? accent.opacity(0.9) : .white.opacity(hovered ? 0.23 : 0.11), lineWidth: focused || expanded ? 1.5 : 1) }
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
                .background { GeometryReader { geometry in Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { _, value in width = value } } }
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    IrisDropdownPanel(title: title, selected: selection, options: options, footerTitle: footerTitle, select: { value in
                        selection = value; expanded = false
                    }, close: { expanded = false }, footerAction: {
                        expanded = false; footerAction?()
                    })
                    .frame(width: min(440, max(260, width)))
                    .environment(\.irisControlAccent, accent)
                    .preferredColorScheme(.dark)
                    .presentationBackground(IrisDesign.surface)
                }
                .accessibilityLabel(title).accessibilityValue(valueLabel)
                .accessibilityHint("Opens Iris choices")
        }.frame(maxWidth: .infinity, alignment: .leading).opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: expanded)
    }
}

/// Fully custom popover content: no Menu, NSMenu or native Picker.
struct IrisDropdownPanel<Value: Hashable>: View {
    let title: String
    let selected: Value
    let options: [IrisPickerOption<Value>]
    var footerTitle: String? = nil
    let select: (Value) -> Void
    let close: () -> Void
    var footerAction: () -> Void = {}
    @State private var query = ""
    @State private var active: Value?
    @State private var keyboardNavigation = false
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Environment(\.irisControlAccent) private var accent
    private var searchable: Bool { options.count >= 8 }
    private var filtered: [IrisPickerOption<Value>] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || ($0.detail?.localizedCaseInsensitiveContains(term) ?? false) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").irisSymbolStyle().font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary).help("Close choices").accessibilityLabel("Close choices")
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            if searchable {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").irisSymbolStyle().foregroundStyle(accent)
                    TextField("Filter choices…", text: $query).textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused).accessibilityLabel("Filter \(title)").onSubmit { commit() }
                }.padding(11).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider().overlay(.white.opacity(0.05))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if filtered.isEmpty { Text("No matching choices").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary).frame(maxWidth: .infinity).padding(.vertical, 24) }
                        ForEach(filtered) { option in
                            Button { select(option.value) } label: {
                                HStack(spacing: 12) {
                                    if let symbol = option.symbol { Image(systemName: symbol).irisSymbolStyle().foregroundStyle(accent).frame(width: 20) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.title).font(.system(size: 13, weight: option.value == selected ? .semibold : .regular)).fixedSize(horizontal: false, vertical: true)
                                        if let detail = option.detail { Text(detail).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark").irisSymbolStyle().font(.system(size: 11, weight: .bold)).foregroundStyle(accent).opacity(option.value == selected ? 1 : 0).accessibilityHidden(true)
                                }.foregroundStyle(IrisDesign.text).padding(.horizontal, 12).padding(.vertical, 12).frame(minHeight: 42)
                                    .background(option.value == active ? accent.opacity(0.16) : option.value == selected ? accent.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                    .contentShape(RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).id(option.value).onHover { over in if over { keyboardNavigation = false; active = option.value } }
                                .accessibilityAddTraits(option.value == selected ? .isSelected : [])
                        }
                    }.padding(8)
                }.frame(height: min(300, CGFloat(max(1, filtered.count)) * 54 + 16))
                    .onChange(of: active) { _, value in if keyboardNavigation, let value { proxy.scrollTo(value, anchor: .center) } }
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
            if let footerTitle {
                Divider()
                Button(action: footerAction) { HStack { Text(footerTitle); Spacer(); Image(systemName: "arrow.up.right").irisSymbolStyle() }.font(.system(size: 12, weight: .medium)).padding(14).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(accent)
            }
        }.background(LinearGradient(colors: [IrisDesign.surface, IrisDesign.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
            .foregroundStyle(IrisDesign.text).focusable().focusEffectDisabled().focused($listFocused)
            .onAppear { active = selected; if searchable { searchFocused = true } else { listFocused = true } }
            .onChange(of: query) { _, _ in keyboardNavigation = true; active = filtered.first?.value }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.return) { commit(); return .handled }
            .onKeyPress(.escape) { close(); return .handled }
    }
    private func commit() {
        if let active, filtered.contains(where: { $0.value == active }) { select(active) }
    }
    private func move(_ direction: Int) {
        guard !filtered.isEmpty else { return }
        let index = active.flatMap { value in filtered.firstIndex(where: { $0.value == value }) } ?? (direction > 0 ? -1 : filtered.count)
        keyboardNavigation = true
        active = filtered[min(filtered.count - 1, max(0, index + direction))].value
    }
}

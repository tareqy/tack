import SwiftUI

/// The app-wide card-detail presentation preference. Raw values are persisted wire format and
/// are also accepted by the UI-test launch override, so never rename them.
enum CardDetailPresentation: String, CaseIterable, Identifiable {
    case sheet
    case sidePanel = "side-panel"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sheet: "Sheet"
        case .sidePanel: "Side Panel"
        }
    }

    /// Missing, corrupt, or future values keep the established sheet behavior instead of making
    /// card details unavailable. This is the single decoding path for persisted and launch values.
    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .sheet
    }
}

/// Native macOS Settings content for choosing how newly opened card details are presented.
/// Changing this value does not mutate an already-open editor; `RootView` snapshots the preference
/// when it starts a presentation and consults this setting again on the next open.
struct CardDetailSettingsView: View {
    @AppStorage private var storedPresentation: String

    init(defaultsKey: String) {
        _storedPresentation = AppStorage(
            wrappedValue: CardDetailPresentation.sheet.rawValue,
            defaultsKey
        )
    }

    var body: some View {
        Form {
            Picker("Open card details in", selection: presentation) {
                ForEach(CardDetailPresentation.allCases) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier(AccessibilityID.cardDetailSettingsPicker)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 360)
    }

    private var presentation: Binding<CardDetailPresentation> {
        Binding(
            get: { CardDetailPresentation(storedValue: storedPresentation) },
            set: { storedPresentation = $0.rawValue }
        )
    }
}

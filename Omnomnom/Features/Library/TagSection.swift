import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// The Tags section of an editor: every tag already in use as a chip that toggles on
/// and off, and a field for one that does not exist yet.
///
/// Works on names, not on models, so the draft it edits stays a value type and nothing
/// reaches the store until the editor saves. `Tag.named(_:in:)` then decides whether a
/// name is an existing tag or a new one.
struct TagSection: View {
    @Binding var tags: [String]

    @Query(sort: \Tag.name) private var stored: [Tag]
    @State private var newTag = ""

    /// Every tag worth offering: the ones in the store, plus any this draft has added
    /// that are not stored yet.
    private var chips: [String] {
        var names = stored.map(\.name)
        for tag in tags where !names.contains(where: { matches($0, tag) }) {
            names.append(tag)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var trimmedNew: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section {
            if !chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chips, id: \.self) { name in
                        Button {
                            toggle(name)
                        } label: {
                            Label(name, systemImage: isOn(name) ? "checkmark" : "plus")
                        }
                        .buttonStyle(.bordered)
                        .tint(isOn(name) ? Color.accentColor : Color.secondary)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(isOn(name) ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("New tag", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { add() }
                Button("Add", action: add)
                    .buttonStyle(.borderless)
                    .disabled(trimmedNew.isEmpty)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Search the Library for a tag to see everything under it.")
        }
    }

    private func isOn(_ name: String) -> Bool {
        tags.contains { matches($0, name) }
    }

    private func matches(_ one: String, _ other: String) -> Bool {
        one.caseInsensitiveCompare(other) == .orderedSame
    }

    private func toggle(_ name: String) {
        if isOn(name) {
            tags.removeAll { matches($0, name) }
        } else {
            tags.append(name)
        }
    }

    /// Adds what was typed, unless the draft already carries it under any casing. The
    /// field is cleared either way, so a repeat is not left sitting there looking unsaved.
    private func add() {
        let name = trimmedNew
        guard !name.isEmpty else { return }
        if !isOn(name) {
            tags.append(name)
        }
        newTag = ""
    }
}

#if DEBUG
private struct TagSectionPreview: View {
    @State private var tags: [String]

    init(tags: [String]) {
        _tags = State(initialValue: tags)
    }

    var body: some View {
        Form {
            TagSection(tags: $tags)
            Section("Chosen") {
                Text(tags.isEmpty ? "None" : tags.joined(separator: ", "))
            }
        }
    }
}

#Preview("Nothing chosen") {
    TagSectionPreview(tags: [])
        .previewEnvironment(seed: .library)
}

#Preview("Two chosen") {
    TagSectionPreview(tags: ["breakfast", "meal prep"])
        .previewEnvironment(seed: .library)
}

#Preview("Accessibility 5") {
    TagSectionPreview(tags: ["breakfast"])
        .previewEnvironment(seed: .library)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif

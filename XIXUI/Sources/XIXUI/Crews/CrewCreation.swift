// Crew creation (Pass 7 §4): name it, add people, done — landing on the empty board with the invite
// as the only filled element. Private is said once, on the naming step, where it matters.
import SwiftUI

public struct CrewNameStep: View {
    @Binding public var name: String
    public let suggestions: [String]
    public let onNext: () -> Void
    public let onBack: (() -> Void)?

    public init(name: Binding<String>, suggestions: [String], onNext: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self._name = name; self.suggestions = suggestions; self.onNext = onNext; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            XIXBar(kicker: "NEW CREW · 1 OF 3", title: nil, onBack: onBack)
            VStack(alignment: .leading, spacing: 0) {
                Text("Name it").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                TextField("Sunday Foursome", text: $name)
                    .font(XIXType.body(17)).padding(.horizontal, 16).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface))
                    .padding(.horizontal, 12)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("crewName")
                if !suggestions.isEmpty {
                    Text("SUGGESTED").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(suggestions, id: \.self) { s in SelectChip(text: s, selected: name == s) { name = s } }
                    }
                    .padding(.horizontal, 20)
                }
                Text("Crews are private. Only people you add can see the board, and it never appears in the global rankings.")
                    .font(XIXType.body(12)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.top, 22)
                Spacer(minLength: 20)
                PrimaryCapsule(title: "Next", action: onNext)
                    .padding(.horizontal, 12).padding(.bottom, 18)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("crewNameNext")
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }
}

public struct CrewPeopleStep: View {
    public struct Person: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var sub: String
        public init(id: UUID, name: String, sub: String) { self.id = id; self.name = name; self.sub = sub }
    }

    public let crewName: String
    public let added: [Person]
    public let recent: [Person]
    public let link: String
    public let onAdd: (Person) -> Void
    public let onRemove: (Person) -> Void
    public let onDone: () -> Void
    public let onBack: (() -> Void)?

    public init(crewName: String, added: [Person], recent: [Person], link: String,
                onAdd: @escaping (Person) -> Void, onRemove: @escaping (Person) -> Void,
                onDone: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.crewName = crewName; self.added = added; self.recent = recent; self.link = link
        self.onAdd = onAdd; self.onRemove = onRemove; self.onDone = onDone; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            XIXBar(kicker: "\(crewName.uppercased()) · 2 OF 3", title: nil, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add people").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                    ForEach(added) { person in
                        HStack(spacing: 14) {
                            Text(ScorecardModel.initials(for: person.name)).trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.green)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(XIXColor.cream).overlay(Circle().strokeBorder(XIXColor.green, lineWidth: 1)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.name).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                                Text(person.sub).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                            }
                            Spacer()
                            Button { onRemove(person) } label: {
                                Text("×").font(XIXType.body(20)).foregroundStyle(XIXColor.muted).frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                    }
                    let offer = recent.filter { r in !added.contains { $0.id == r.id } }
                    if !offer.isEmpty {
                        Text("RECENT PLAYERS").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                            ForEach(offer) { person in
                                SelectChip(text: person.name) { onAdd(person) }
                                    .accessibilityIdentifier("crewAdd-\(person.name)")
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OR SHARE A JOIN LINK").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                        Text(link).font(XIXType.number(15, weight: .bold)).foregroundStyle(XIXColor.ink)
                        Text("Anyone with the link joins the crew. A round anywhere counts here.")
                            .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(XIXColor.cream))
                    .padding(.horizontal, 12).padding(.top, 22)
                }
            }
            PrimaryCapsule(title: "Create crew", action: onDone)
                .padding(.horizontal, 12).padding(.bottom, 18)
                .accessibilityIdentifier("crewCreate")
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }
}

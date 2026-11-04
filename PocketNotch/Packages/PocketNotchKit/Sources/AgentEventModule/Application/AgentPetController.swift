import Combine
import Foundation

@MainActor
public final class AgentPetController: ObservableObject {
    @Published public private(set) var pets: [PetDescriptor] = []

    private let settings: AgentActivitySettings
    private let library: PetLibrary
    private var settingsCancellable: AnyCancellable?

    public init(settings: AgentActivitySettings, library: PetLibrary = PetLibrary()) {
        self.settings = settings
        self.library = library
        pets = library.discover()
        settingsCancellable = settings.$petBindings.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func refresh() {
        pets = library.discover()
        clearMissingBindings()
    }

    public func selectedPetID(for agent: AgentIdentity) -> String? {
        settings.petBindings[agent.rawValue]
    }

    public func selectedPet(for agentID: String) -> PetDescriptor? {
        if let selectedID = settings.petBindings[agentID],
           let selected = pets.first(where: { $0.id == selectedID }) {
            return selected
        }
        if let agent = AgentIdentity(rawValue: agentID) {
            if let agentDefault = pets.first(where: { $0.defaultAgentIDs.contains(agent) }) {
                return agentDefault
            }
            if let bundled = pets.first(where: {
                $0.source == .bundled && manifest($0.manifest, belongsTo: agent)
            }) {
                return bundled
            }
        }
        return pets.first(where: { normalizedManifestID($0) == "kun-like" })
            ?? pets.first(where: {
                $0.source == .bundled && normalizedManifestID($0) == "default"
            })
    }

    public func selectPet(id: String?, for agent: AgentIdentity) {
        settings.setPetBinding(id, for: agent.rawValue)
    }

    public func applyPetToAll(id: String?) {
        for agent in AgentIdentity.allCases {
            settings.setPetBinding(id, for: agent.rawValue)
        }
    }

    @discardableResult
    public func importPet(from packageURL: URL) throws -> PetDescriptor {
        let imported = try library.importPackage(at: packageURL)
        refresh()
        return imported
    }

    @discardableResult
    public func createCustomPet(
        displayName: String,
        animationURLs: [PetAnimationState: URL]
    ) throws -> PetDescriptor {
        let pet = try library.createCustomPet(
            displayName: displayName,
            animationURLs: animationURLs
        )
        refresh()
        return pet
    }

    public func deletePet(_ pet: PetDescriptor) throws {
        try library.delete(pet)
        for agent in AgentIdentity.allCases where settings.petBindings[agent.rawValue] == pet.id {
            settings.setPetBinding(nil, for: agent.rawValue)
        }
        refresh()
    }

    private func clearMissingBindings() {
        let availableIDs = Set(pets.map(\.id))
        for agent in AgentIdentity.allCases {
            guard let id = settings.petBindings[agent.rawValue], !availableIDs.contains(id) else {
                continue
            }
            settings.setPetBinding(nil, for: agent.rawValue)
        }
    }

    private func manifest(_ manifest: PetManifest, belongsTo agent: AgentIdentity) -> Bool {
        let agentName = agent.rawValue.lowercased()
        return manifest.id.lowercased().contains(agentName)
            || manifest.displayName.lowercased().contains(agentName)
    }

    private func normalizedManifestID(_ pet: PetDescriptor) -> String {
        pet.manifest.id.lowercased()
    }
}

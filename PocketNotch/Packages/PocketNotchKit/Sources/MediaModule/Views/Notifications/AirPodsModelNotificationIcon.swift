import AppKit
import PocketNotchCore
import SceneKit
import SwiftUI

private final class TransparentSCNView: SCNView {
    override var isOpaque: Bool { false }
}

enum AirPodsModelPresentation {
    case notificationPair
    case compactLeading

    private static let leftEarbudNodeName = "BLvfImZvTRtJYtd"
    private static let rightEarbudNodeName = "bqtvQbjelRVbbzz"

    var hiddenEarbudNodeNames: Set<String> {
        switch self {
        case .notificationPair:
            []
        case .compactLeading:
            [Self.rightEarbudNodeName]
        }
    }

    var boundingNodeName: String {
        switch self {
        case .notificationPair:
            "YamPaavUOjSVJHE"
        case .compactLeading:
            Self.leftEarbudNodeName
        }
    }

    var pairCompression: CGFloat? {
        switch self {
        case .notificationPair:
            0.85
        case .compactLeading:
            nil
        }
    }

    var pivotScale: CGFloat {
        switch self {
        case .notificationPair:
            2
        case .compactLeading:
            2.55
        }
    }

    var orthographicScale: Double {
        switch self {
        case .notificationPair:
            4.5
        case .compactLeading:
            2.65
        }
    }

    var usesExplicitLights: Bool {
        self == .compactLeading
    }

    var lightingEnvironmentIntensity: CGFloat {
        switch self {
        case .notificationPair:
            1.1
        case .compactLeading:
            0.85
        }
    }

    var sceneBackgroundColor: NSColor {
        switch self {
        case .notificationPair:
            .clear
        case .compactLeading:
            .black
        }
    }
}

enum AirPodsModelSceneFactory {
    static let cameraNodeName = "airpods-camera"
    static let pivotNodeName = "airpods-rotation-pivot"
    private static let cacheLock = NSLock()
    private static var cachedScenes: [AirPodsModelPresentation: SCNScene] = [:]

    static func makeScene(presentation: AirPodsModelPresentation = .notificationPair) -> SCNScene? {
        if let cached = cachedScene(for: presentation) {
            return clone(cached)
        }

        guard let scene = buildScene(presentation: presentation) else { return nil }
        store(scene, for: presentation)
        return clone(scene)
    }

    private static func buildScene(presentation: AirPodsModelPresentation) -> SCNScene? {
        guard let url = Bundle.module.url(forResource: "airpods-pro", withExtension: "usdz") else {
            return nil
        }

        do {
            let scene = try SCNScene(url: url, options: nil)
            scene.background.contents = presentation.sceneBackgroundColor
            guard let assetRoot = scene.rootNode.childNode(
                withName: "WuGhFNDqVOYCPCI",
                recursively: true
            ) else {
                return scene
            }

            // The USD scene has two sibling components under IvbAUpgLKGKfWua:
            // YamPaavUOjSVJHE (both earbuds) and hXJOJrkFTZXXxnW (the case).
            assetRoot.childNode(
                withName: "hXJOJrkFTZXXxnW",
                recursively: true
            )?.isHidden = true

            for name in ["BLvfImZvTRtJYtd", "bqtvQbjelRVbbzz"] {
                guard let earbud = assetRoot.childNode(withName: name, recursively: true) else {
                    continue
                }
                if presentation.hiddenEarbudNodeNames.contains(name) {
                    earbud.isHidden = true
                }
                var position = earbud.position
                if let pairCompression = presentation.pairCompression {
                    position.x *= pairCompression
                }
                earbud.position = position
                applyDefaultRotation(to: earbud, named: name)
            }

            let earbudRoot = assetRoot.childNode(
                withName: presentation.boundingNodeName,
                recursively: true
            )
            var minimum = SCNVector3Zero
            var maximum = SCNVector3Zero
            earbudRoot?.__getBoundingBoxMin(&minimum, max: &maximum)

            let center = SCNVector3(
                (minimum.x + maximum.x) * 0.5,
                (minimum.y + maximum.y) * 0.5,
                (minimum.z + maximum.z) * 0.5
            )
            let pivot = SCNNode()
            pivot.name = pivotNodeName
            assetRoot.removeFromParentNode()
            scene.rootNode.addChildNode(pivot)
            pivot.addChildNode(assetRoot)
            assetRoot.position = SCNVector3(-center.x, -center.y, -center.z)
            pivot.scale = SCNVector3(
                presentation.pivotScale,
                presentation.pivotScale,
                presentation.pivotScale
            )

            let cameraNode = SCNNode()
            cameraNode.name = cameraNodeName
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = presentation.orthographicScale
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 10)
            cameraNode.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(cameraNode)

            if presentation.usesExplicitLights {
                addCompactLights(to: scene)
            }
            scene.lightingEnvironment.intensity = presentation.lightingEnvironmentIntensity
            return scene
        } catch {
            return nil
        }
    }

    private static func cachedScene(for presentation: AirPodsModelPresentation) -> SCNScene? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedScenes[presentation]
    }

    private static func store(_ scene: SCNScene, for presentation: AirPodsModelPresentation) {
        cacheLock.lock()
        cachedScenes[presentation] = scene
        cacheLock.unlock()
    }

    private static func clone(_ template: SCNScene) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = template.background.contents
        scene.lightingEnvironment.contents = template.lightingEnvironment.contents
        scene.lightingEnvironment.intensity = template.lightingEnvironment.intensity
        for child in template.rootNode.childNodes {
            scene.rootNode.addChildNode(child.clone())
        }
        return scene
    }

    private static func applyDefaultRotation(to earbud: SCNNode, named earbudNodeName: String) {
        guard let parent = earbud.parent else { return }

        let wrapper = SCNNode()
        wrapper.name = "\(earbud.name ?? "airpod")-default-rotation"
        wrapper.position = earbud.position
        wrapper.eulerAngles.y = defaultYRotation(for: earbudNodeName)

        earbud.removeFromParentNode()
        earbud.position = SCNVector3Zero
        parent.addChildNode(wrapper)
        wrapper.addChildNode(earbud)
    }

    private static func defaultYRotation(for earbudNodeName: String) -> CGFloat {
        switch earbudNodeName {
        case "BLvfImZvTRtJYtd":
            -.pi / 36
        case "bqtvQbjelRVbbzz":
            .pi / 36
        default:
            0
        }
    }

    private static func addCompactLights(to scene: SCNScene) {
        let ambientNode = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor.white
        ambientLight.intensity = 140
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = NSColor.white
        keyLight.intensity = 430
        keyNode.light = keyLight
        keyNode.position = SCNVector3(2.5, 4, 8)
        keyNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyNode)
    }
}

/// Renders the two earbuds from the bundled USDZ. The charging case is a
/// separate component in the source scene and is disabled before presentation.
struct AirPodsModelNotificationIcon: NSViewRepresentable {
    private static let rotationActionKey = "airpods-horizontal-rotation"

    let reduceMotion: Bool
    let isActive: Bool

    func makeNSView(context: Context) -> SCNView {
        let view = TransparentSCNView(frame: .zero)
        view.backgroundColor = .clear
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.preferredFramesPerSecond = DisplayRefreshRateMonitor.shared.preferredFramesPerSecond
        view.scene = AirPodsModelSceneFactory.makeScene()
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: AirPodsModelSceneFactory.cameraNodeName,
            recursively: true
        )
        updateAnimation(for: view)
        return view
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Void) {
        view.scene?.rootNode.removeAllActions()
        view.pointOfView = nil
        view.scene = nil
        view.isPlaying = false
    }

    func updateNSView(_ view: SCNView, context: Context) {
        updateAnimation(for: view)
    }

    private func updateAnimation(for view: SCNView) {
        guard let pivot = view.scene?.rootNode.childNode(
            withName: AirPodsModelSceneFactory.pivotNodeName,
            recursively: true
        ) else {
            return
        }

        guard !reduceMotion, isActive else {
            pivot.removeAction(forKey: Self.rotationActionKey)
            pivot.isPaused = false
            return
        }

        pivot.isPaused = false
        guard pivot.action(forKey: Self.rotationActionKey) == nil else { return }

        let rotation = SCNAction.rotateBy(
            x: 0,
            y: CGFloat.pi * 2,
            z: 0,
            duration: AudioOutputDeviceSnapshot.airPodsProRotationDuration
        )
        pivot.runAction(
            .repeatForever(rotation),
            forKey: Self.rotationActionKey
        )
    }
}

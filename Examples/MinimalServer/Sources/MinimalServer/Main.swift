import Foundation
import WaylandServer
import WaylandProtocol

private final class CompositorOwner {
    let owner: ServerObject<WlCompositor>
    let subscription: ServerRequestSubscription
    init(owner: consuming ServerObject<WlCompositor>, subscription: consuming ServerRequestSubscription) {
        self.owner = owner; self.subscription = subscription
    }
}
private final class SurfaceOwner {
    let owner: ServerObject<WlSurface>
    let subscription: ServerRequestSubscription
    init(owner: consuming ServerObject<WlSurface>, subscription: consuming ServerRequestSubscription) {
        self.owner = owner; self.subscription = subscription
    }
}
private final class ServerApplication {
    let display: ServerDisplay
    var compositors: [CompositorOwner] = []
    var surfaces: [SurfaceOwner] = []
    var completed = false
    init() throws { display = try ServerDisplay() }
    func bind(_ identifier: consuming ServerNewIdentifier<WlCompositor>) throws {
        let owner = try identifier.accept()
        let subscription = try owner.onRequest { [weak self] request in
            guard let self else { return }
            switch consume request {
            case .createSurface(let identifier):
                let surface = try identifier.accept()
                let subscription = try surface.onRequest { [weak self] request in
                    switch consume request {
                    case .commit: break
                    case .destroy: self?.completed = true
                    default: throw ServerExampleError.unsupportedRequest
                    }
                }
                self.surfaces.append(SurfaceOwner(owner: surface, subscription: subscription))
            default: throw ServerExampleError.unsupportedRequest
            }
        }
        compositors.append(CompositorOwner(owner: owner, subscription: subscription))
    }
    enum ServerExampleError: Error { case unsupportedRequest, timeout, incompleteCleanup }
}
@main struct MinimalServer {
    static func main() throws {
        let application = try ServerApplication()
        let global = try application.display.addGlobal(as: WlCompositor.self, version: 1) { [weak application] identifier in
            guard let application else { return }
            try application.bind(identifier)
        }
        let socket = try application.display.addAutomaticSocket()
        FileHandle.standardOutput.write(Data((socket + "\n").utf8))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !application.completed && ContinuousClock.now < deadline { try application.display.dispatch(timeoutMilliseconds: 100) }
        application.display.requestClose()
        let snapshot = try application.display.snapshot()
        guard snapshot.retainedRecords == 0 else { throw ServerApplication.ServerExampleError.incompleteCleanup }
        guard application.completed else { throw ServerApplication.ServerExampleError.timeout }
        withExtendedLifetime(global) {}
        print("Typed surface lifecycle completed; all server ownership records retired.")
    }
}

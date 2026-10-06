import Flutter
import MapKit
import UIKit

/// MapKit only displays/selects coordinates. Device location stays in Dart.
final class NativeChatLocationMapFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        NativeChatLocationMap(
            frame: frame,
            viewId: viewId,
            messenger: messenger,
            parameters: args as? [String: Any] ?? [:]
        )
    }
}

private final class ChatLocationMapContainer: UIView {
    var onAttached: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onAttached?() }
    }
}

private final class NativeChatLocationMap: NSObject,
    FlutterPlatformView, MKMapViewDelegate, UIGestureRecognizerDelegate {
    private let container: ChatLocationMapContainer
    private var map: MKMapView?
    private var channel: FlutterMethodChannel?
    private var selectedPin: MKPointAnnotation?
    private var tapRecognizer: UITapGestureRecognizer?
    private var panRecognizer: UIPanGestureRecognizer?
    private var active = true
    private var disposed = false
    private var readySent = false
    private var readyScheduled = false
    private var eventGeneration = 0
    private var userPanning = false
    private var pendingUserRegion = false
    private var programmaticChange = false

    init(
        frame: CGRect,
        viewId: Int64,
        messenger: FlutterBinaryMessenger,
        parameters: [String: Any]
    ) {
        container = ChatLocationMapContainer(frame: frame)
        let mapView = MKMapView(frame: container.bounds)
        map = mapView
        channel = FlutterMethodChannel(
            name: "openim/chat-location-map/\(viewId)", binaryMessenger: messenger)
        super.init()

        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.mapType = .standard
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.delegate = self
        container.addSubview(mapView)
        setStyle(dark: parameters["dark"] as? Bool ?? false)

        let tap = UITapGestureRecognizer(target: self, action: #selector(onMapTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        mapView.addGestureRecognizer(tap)
        tapRecognizer = tap
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onMapPan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        mapView.addGestureRecognizer(pan)
        panRecognizer = pan

        if let coordinate = Self.coordinate(parameters) {
            move(to: coordinate, zoom: 16)
        } else {
            // An unselected world map must never become an outgoing location.
            mapView.setVisibleMapRect(MKMapRect.world, animated: false)
        }
        container.onAttached = { [weak self] in self?.scheduleReady() }
        channel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self, !self.disposed else {
                result(nil)
                return
            }
            self.handle(call, result: result)
        }
    }

    func view() -> UIView { container }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let parameters = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "move":
            guard let coordinate = Self.coordinate(parameters) else {
                result(FlutterError(code: "INVALID_COORDINATE", message: "Invalid map coordinate", details: nil))
                return
            }
            let zoom = (parameters["zoom"] as? NSNumber)?.doubleValue ?? 16
            move(to: coordinate, zoom: zoom)
            result(nil)
        case "style":
            setStyle(dark: parameters["dark"] as? Bool ?? false)
            result(nil)
        case "status":
            result(["error": NSNull()])
        case "setActive":
            active = parameters["active"] as? Bool ?? false
            eventGeneration += 1
            userPanning = false
            pendingUserRegion = false
            map?.isUserInteractionEnabled = active
            if active { scheduleReady() }
            result(nil)
        case "dispose":
            disposeView()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setStyle(dark: Bool) {
        container.overrideUserInterfaceStyle = dark ? .dark : .light
        map?.overrideUserInterfaceStyle = dark ? .dark : .light
    }

    private func move(to coordinate: CLLocationCoordinate2D, zoom: Double) {
        guard !disposed, let mapView = map else { return }
        eventGeneration += 1
        userPanning = false
        pendingUserRegion = false
        updatePin(coordinate)
        let safeZoom = zoom.isFinite ? min(20, max(1, zoom)) : 16
        let span = min(160, max(0.0005, 360 / pow(2, safeZoom)))
        programmaticChange = true
        mapView.setRegion(
            MKCoordinateRegion(center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)),
            animated: false)
        programmaticChange = false
    }

    private func updatePin(_ coordinate: CLLocationCoordinate2D) {
        guard !disposed, let mapView = map else { return }
        if let pin = selectedPin {
            pin.coordinate = coordinate
        } else {
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            selectedPin = pin
            mapView.addAnnotation(pin)
        }
    }

    @objc private func onMapTap(_ gesture: UITapGestureRecognizer) {
        guard active, !disposed, gesture.state == .ended, let mapView = map else { return }
        let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
        guard Self.valid(coordinate) else { return }
        eventGeneration += 1
        userPanning = false
        pendingUserRegion = false
        updatePin(coordinate)
        programmaticChange = true
        mapView.setCenter(coordinate, animated: false)
        programmaticChange = false
        emitSelection(coordinate)
    }

    @objc private func onMapPan(_ gesture: UIPanGestureRecognizer) {
        guard active, !disposed else { return }
        switch gesture.state {
        case .began:
            // Only an actual user pan opens this fence; Dart moves never do.
            eventGeneration += 1
            userPanning = true
            pendingUserRegion = true
        case .ended:
            userPanning = false
            let generation = eventGeneration
            // MapKit can report its final region before our observer ends.
            // Also accept this center if no later region callback is delivered.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.active, !self.disposed,
                    self.eventGeneration == generation, self.pendingUserRegion,
                    !self.userPanning, let mapView = self.map else { return }
                self.updatePin(mapView.centerCoordinate)
                self.emitSelection(mapView.centerCoordinate)
            }
        case .cancelled, .failed:
            userPanning = false
            pendingUserRegion = false
            eventGeneration += 1
        default:
            break
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        guard active, !disposed, !programmaticChange, pendingUserRegion else { return }
        if Self.valid(mapView.centerCoordinate) { updatePin(mapView.centerCoordinate) }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard active, !disposed, !programmaticChange,
            pendingUserRegion, !userPanning, Self.valid(mapView.centerCoordinate) else { return }
        pendingUserRegion = false
        updatePin(mapView.centerCoordinate)
        emitSelection(mapView.centerCoordinate)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        let identifier = "chat-location-selected"
        let pin = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        pin.annotation = annotation
        pin.markerTintColor = .systemBlue
        pin.glyphImage = UIImage(systemName: "mappin")
        pin.canShowCallout = false
        pin.isDraggable = false
        return pin
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    private func emitSelection(_ coordinate: CLLocationCoordinate2D) {
        guard active, !disposed, Self.valid(coordinate) else { return }
        channel?.invokeMethod("onSelected", arguments: [
            "latitude": coordinate.latitude, "longitude": coordinate.longitude])
    }

    private func scheduleReady() {
        guard !disposed, active, !readySent, !readyScheduled,
            container.window != nil else { return }
        readyScheduled = true
        let generation = eventGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.disposed else { return }
            self.readyScheduled = false
            guard self.active, self.container.window != nil else { return }
            if self.eventGeneration != generation {
                self.scheduleReady()
                return
            }
            self.readySent = true
            self.channel?.invokeMethod("onReady", arguments: nil)
        }
    }

    private static func coordinate(_ values: [String: Any]) -> CLLocationCoordinate2D? {
        guard let latitude = values["latitude"] as? NSNumber,
            let longitude = values["longitude"] as? NSNumber else { return nil }
        let coordinate = CLLocationCoordinate2D(
            latitude: latitude.doubleValue, longitude: longitude.doubleValue)
        return valid(coordinate) ? coordinate : nil
    }

    private static func valid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && CLLocationCoordinate2DIsValid(coordinate)
    }

    private func disposeView() {
        guard !disposed else { return }
        disposed = true
        active = false
        eventGeneration += 1
        userPanning = false
        pendingUserRegion = false
        container.onAttached = nil
        channel?.setMethodCallHandler(nil)
        channel = nil
        if let mapView = map {
            mapView.delegate = nil
            mapView.isUserInteractionEnabled = false
            if let tap = tapRecognizer { mapView.removeGestureRecognizer(tap) }
            if let pan = panRecognizer { mapView.removeGestureRecognizer(pan) }
            mapView.removeAnnotations(mapView.annotations)
            mapView.removeFromSuperview()
        }
        tapRecognizer = nil
        panRecognizer = nil
        selectedPin = nil
        map = nil
    }

    deinit { disposeView() }
}

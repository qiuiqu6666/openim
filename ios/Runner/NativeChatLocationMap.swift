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
    private var placeSearch: MKLocalSearch?
    private var placeSearchReply: FlutterResult?
    private var readOnly = false
    private var detail = false
    private var userPin: MKPointAnnotation?
    private var snapshotter: MKMapSnapshotter?
    private var snapshotReply: FlutterResult?
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
        readOnly = parameters["readOnly"] as? Bool ?? false
        detail = parameters["detail"] as? Bool ?? false

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
        case "snapshot":
            captureSnapshot(result)
        case "searchPlaces":
            searchPlaces(parameters, result: result)
        case "move":
            guard let coordinate = Self.coordinate(parameters) else {
                result(FlutterError(code: "INVALID_COORDINATE", message: "Invalid map coordinate", details: nil))
                return
            }
            let zoom = (parameters["zoom"] as? NSNumber)?.doubleValue ?? 16
            move(to: coordinate, zoom: zoom)
            result(nil)
        case "detailView":
            guard detail, let mapView = map else { result(nil); return }
            mapView.mapType = parameters["satellite"] as? Bool == true ? .hybrid : .standard
            let top = (parameters["topInset"] as? NSNumber)?.doubleValue ?? 0
            let bottom = (parameters["bottomInset"] as? NSNumber)?.doubleValue ?? 0
            mapView.layoutMargins = UIEdgeInsets(top: top, left: 16, bottom: bottom, right: 16)
            if let lat = parameters["userLatitude"], let lon = parameters["userLongitude"],
               let coordinate = Self.coordinate(["latitude": lat, "longitude": lon]) {
                if let pin = userPin { pin.coordinate = coordinate }
                else { let pin = MKPointAnnotation(); pin.coordinate = coordinate; userPin = pin; mapView.addAnnotation(pin) }
            }
            if parameters["moveCamera"] as? Bool == true, let coordinate = Self.coordinate(parameters) {
                let region = MKCoordinateRegion(center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.0055, longitudeDelta: 0.0055))
                mapView.setRegion(region, animated: false)
            }
            result(nil)
        case "style":
            setStyle(dark: parameters["dark"] as? Bool ?? false)
            result(nil)
        case "status":
            result(["error": NSNull()])
        case "setActive":
            active = parameters["active"] as? Bool ?? false
            if !active { cancelPlaceSearch() }
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

    private func captureSnapshot(_ result: @escaping FlutterResult) {
        guard let map = map, let pin = selectedPin, active, !disposed else {
            result(FlutterError(code: "unavailable", message: "Map unavailable", details: nil))
            return
        }
        let options = MKMapSnapshotter.Options()
        options.region = map.region
        options.size = map.bounds.size.width > 0 ? map.bounds.size : CGSize(width: 280, height: 150)
        options.traitCollection = map.traitCollection
        let renderer = MKMapSnapshotter(options: options)
        snapshotter = renderer
        snapshotReply = result
        renderer.start { [weak self] snapshot, error in
            guard let self = self, self.snapshotter === renderer, !self.disposed else { return }
            self.snapshotter = nil
            self.snapshotReply = nil
            guard let snapshot = snapshot, error == nil else {
                result(FlutterError(code: "snapshotUnavailable", message: "Snapshot unavailable", details: nil))
                return
            }
            let image = UIGraphicsImageRenderer(size: snapshot.image.size).image { _ in
                snapshot.image.draw(at: .zero)
                let point = snapshot.point(for: pin.coordinate)
                UIImage(systemName: "mappin.circle.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: point.x - 16, y: point.y - 32, width: 32, height: 32))
            }
            guard let bytes = image.pngData() else {
                result(FlutterError(code: "snapshotUnavailable", message: "Snapshot unavailable", details: nil))
                return
            }
            result(FlutterStandardTypedData(bytes: bytes))
        }
    }

    private func cancelPlaceSearch() {
        placeSearch?.cancel()
        placeSearch = nil
        let reply = placeSearchReply
        placeSearchReply = nil
        reply?(FlutterError(code: "cancelled", message: "Search cancelled", details: nil))
    }

    private func searchPlaces(_ values: [String: Any], result: @escaping FlutterResult) {
        cancelPlaceSearch()
        guard active, !disposed else {
            result(FlutterError(code: "unavailable", message: "Map unavailable", details: nil))
            return
        }
        let query = (values["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let center = Self.coordinate(values) ?? map?.centerCoordinate
        let search: MKLocalSearch
        if query.isEmpty, let center = center {
            search = MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: center, radius: 1000))
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let center = center {
                request.region = MKCoordinateRegion(center: center, latitudinalMeters: 50000, longitudinalMeters: 50000)
            }
            search = MKLocalSearch(request: request)
        }
        placeSearch = search
        placeSearchReply = result
        search.start { [weak self] response, error in
            guard let self = self, self.placeSearch === search else { return }
            self.placeSearch = nil
            self.placeSearchReply = nil
            guard self.active, !self.disposed, error == nil, let response = response else {
                result(FlutterError(code: "searchUnavailable", message: "Place search unavailable", details: nil))
                return
            }
            result(response.mapItems.prefix(20).map { item -> [String: Any] in
                let point = item.placemark.coordinate
                return ["id": "\(point.latitude),\(point.longitude):\(item.name ?? "")",
                        "name": item.name ?? "", "address": item.placemark.title ?? "",
                        "latitude": point.latitude, "longitude": point.longitude]
            })
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
        guard !readOnly, active, !disposed, gesture.state == .ended, let mapView = map else { return }
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
        guard !readOnly, active, !disposed else { return }
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
        if annotation === userPin {
            let identifier = "chat-location-device"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 24, height: 24)).fill()
                UIColor.systemBlue.setFill(); UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 18, height: 18)).fill()
            }
            return view
        }
        let identifier = "chat-location-selected"
        let pin = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        pin.annotation = annotation
        pin.markerTintColor = detail ? .systemBlue : .systemGreen
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
        snapshotter?.cancel()
        snapshotter = nil
        snapshotReply?(FlutterError(code: "cancelled", message: "Map closed", details: nil))
        snapshotReply = nil
        cancelPlaceSearch()
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
        userPin = nil
        map = nil
    }

    deinit { disposeView() }
}

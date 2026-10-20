import Flutter
import CoreLocation
import Contacts

final class ChatLocationAddressBridge {
    private let channel: FlutterMethodChannel
    private var requests: [UUID: CLGeocoder] = [:]
    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "openim/location-address", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            guard call.method == "reverse" else { result(FlutterMethodNotImplemented); return }
            guard let args = call.arguments as? [String: Any],
                  let lat = args["latitude"] as? NSNumber, let lon = args["longitude"] as? NSNumber else {
                result(FlutterError(code: "invalid", message: "Invalid coordinate", details: nil)); return
            }
            let coordinate = CLLocationCoordinate2D(latitude: lat.doubleValue, longitude: lon.doubleValue)
            guard coordinate.latitude.isFinite, coordinate.longitude.isFinite, CLLocationCoordinate2DIsValid(coordinate) else {
                result(FlutterError(code: "invalid", message: "Invalid coordinate", details: nil)); return
            }
            let id = UUID(), geocoder = CLGeocoder()
            self.requests[id] = geocoder
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                guard let pending = self?.requests.removeValue(forKey: id) else { return }
                pending.cancelGeocode()
                result(FlutterError(code: "timeout", message: "Address lookup timed out", details: nil))
            }
            let locale = (args["locale"] as? String).map { Locale(identifier: $0) }
            geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), preferredLocale: locale) { [weak self] places, error in
                guard self?.requests.removeValue(forKey: id) != nil else { return }
                guard error == nil, let place = places?.first else {
                    result(FlutterError(code: "unavailable", message: "Address not found", details: nil)); return
                }
                let address: String
                if let postal = place.postalAddress {
                    address = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress).replacingOccurrences(of: "\n", with: " ")
                } else {
                    address = [place.country, place.administrativeArea, place.locality, place.subLocality, place.thoroughfare, place.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                }
                result(["name": place.name ?? "", "address": address])
            }
        }
    }
    deinit { channel.setMethodCallHandler(nil); requests.values.forEach { $0.cancelGeocode() } }
}

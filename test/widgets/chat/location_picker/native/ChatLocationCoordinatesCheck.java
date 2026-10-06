import io.openim.location.ChatLocationCoordinates;

/** Standalone JVM checks; no map SDK, Key, device, or Android permission needed. */
public final class ChatLocationCoordinatesCheck {
    public static void main(String[] arguments) {
        near(39.91022649807321, 116.4037135824225, 39.908823, 116.397470);
        near(31.22845773757727, 121.47822305927693, 31.2304, 121.4737);
        unchanged(40.7128, -74.0060);
        unchanged(48.8566, 2.3522);
        unchanged(0, 0);
        unchanged(-90, -180);
        unchanged(90, 180);
        invalid(Double.NaN, 0);
        invalid(0, Double.POSITIVE_INFINITY);
        invalid(91, 0);
        invalid(0, 181);
        System.out.println("Coordinate checks passed: domestic reference points, overseas identity, boundaries and invalid input.");
    }

    private static void near(double latitude, double longitude, double expectedLatitude, double expectedLongitude) {
        double[] actual = ChatLocationCoordinates.gcj02ToWgs84(latitude, longitude);
        if (Math.abs(actual[0] - expectedLatitude) > 1e-7
                || Math.abs(actual[1] - expectedLongitude) > 1e-7) {
            throw new AssertionError("Domestic coordinate inverse outside tolerance");
        }
    }

    private static void unchanged(double latitude, double longitude) {
        double[] actual = ChatLocationCoordinates.gcj02ToWgs84(latitude, longitude);
        if (actual[0] != latitude || actual[1] != longitude) {
            throw new AssertionError("Overseas coordinate changed");
        }
    }

    private static void invalid(double latitude, double longitude) {
        if (ChatLocationCoordinates.isValid(latitude, longitude)) {
            throw new AssertionError("Invalid coordinate accepted");
        }
        try {
            ChatLocationCoordinates.gcj02ToWgs84(latitude, longitude);
            throw new AssertionError("Invalid inverse accepted");
        } catch (IllegalArgumentException expected) {
            // Expected rejection.
        }
    }
}

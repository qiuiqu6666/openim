package io.openim.location;

/** Coordinate math at the WGS84 / GCJ-02 boundary; has no Android dependency. */
public final class ChatLocationCoordinates {
    private static final double SEMI_MAJOR_AXIS = 6378245.0;
    private static final double ECCENTRICITY_SQUARED = 0.00669342162296594323;

    private ChatLocationCoordinates() {}

    public static boolean isValid(double latitude, double longitude) {
        return !Double.isNaN(latitude) && !Double.isInfinite(latitude)
                && !Double.isNaN(longitude) && !Double.isInfinite(longitude)
                && Math.abs(latitude) <= 90.0 && Math.abs(longitude) <= 180.0;
    }

    public static boolean insideChina(double latitude, double longitude) {
        return isValid(latitude, longitude)
                && longitude >= 72.004 && longitude <= 137.8347
                && latitude >= 0.8293 && latitude <= 55.8271;
    }

    /** Returns latitude, longitude. Coordinates outside China are unchanged. */
    public static double[] gcj02ToWgs84(double latitude, double longitude) {
        if (!isValid(latitude, longitude)) {
            throw new IllegalArgumentException("Invalid coordinate");
        }
        if (!insideChina(latitude, longitude)) return new double[]{latitude, longitude};
        double candidateLatitude = latitude;
        double candidateLongitude = longitude;
        for (int iteration = 0; iteration < 30; iteration++) {
            double[] projected = project(candidateLatitude, candidateLongitude);
            double latitudeError = projected[0] - latitude;
            double longitudeError = projected[1] - longitude;
            candidateLatitude -= latitudeError;
            candidateLongitude -= longitudeError;
            if (Math.abs(latitudeError) < 1e-9 && Math.abs(longitudeError) < 1e-9) break;
        }
        return new double[]{candidateLatitude, candidateLongitude};
    }

    private static double[] project(double latitude, double longitude) {
        double latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0);
        double longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0);
        double radians = latitude / 180.0 * Math.PI;
        double sinLatitude = Math.sin(radians);
        double magic = 1.0 - ECCENTRICITY_SQUARED * sinLatitude * sinLatitude;
        double rootMagic = Math.sqrt(magic);
        latitudeDelta = latitudeDelta * 180.0
                / ((SEMI_MAJOR_AXIS * (1.0 - ECCENTRICITY_SQUARED))
                / (magic * rootMagic) * Math.PI);
        longitudeDelta = longitudeDelta * 180.0
                / (SEMI_MAJOR_AXIS / rootMagic * Math.cos(radians) * Math.PI);
        return new double[]{latitude + latitudeDelta, longitude + longitudeDelta};
    }

    private static double transformLatitude(double x, double y) {
        double result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
                + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
        result += (20.0 * Math.sin(6.0 * x * Math.PI)
                + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
        result += (20.0 * Math.sin(y * Math.PI)
                + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
        result += (160.0 * Math.sin(y / 12.0 * Math.PI)
                + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
        return result;
    }

    private static double transformLongitude(double x, double y) {
        double result = 300.0 + x + 2.0 * y + 0.1 * x * x
                + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
        result += (20.0 * Math.sin(6.0 * x * Math.PI)
                + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
        result += (20.0 * Math.sin(x * Math.PI)
                + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
        result += (150.0 * Math.sin(x / 12.0 * Math.PI)
                + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
        return result;
    }
}

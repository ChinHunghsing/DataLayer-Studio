import Foundation

public struct TelemetrySample: Equatable {
    public var elapsed: TimeInterval
    public var date: Date?
    public var latitude: Double?
    public var longitude: Double?
    public var altitudeMeters: Double?
    public var heartRate: Int?
    public var cadence: Int?
    public var distanceMeters: Double?
    public var speedMetersPerSecond: Double?
    public var powerWatts: Int?
    public var totalCalories: Double?
    public var stepLengthMeters: Double?
    public var temperatureCelsius: Int?

    public init(
        elapsed: TimeInterval,
        date: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitudeMeters: Double? = nil,
        heartRate: Int? = nil,
        cadence: Int? = nil,
        distanceMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        powerWatts: Int? = nil,
        totalCalories: Double? = nil,
        stepLengthMeters: Double? = nil,
        temperatureCelsius: Int? = nil
    ) {
        self.elapsed = elapsed
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.heartRate = heartRate
        self.cadence = cadence
        self.distanceMeters = distanceMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.powerWatts = powerWatts
        self.totalCalories = totalCalories
        self.stepLengthMeters = stepLengthMeters
        self.temperatureCelsius = temperatureCelsius
    }
}

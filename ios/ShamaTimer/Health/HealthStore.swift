import Foundation
import HealthKit

/// Apple Health: запись Mindful Minutes + разрешение на чтение для выгрузки в Life (HealthExporter).
/// Разрешение спрашивается на переднем плане; ошибки молча.
final class HealthStore {
    /// Один HKHealthStore на приложение (его же берёт HealthExporter.shared).
    static let hkStore = HKHealthStore()

    var store: HKHealthStore { Self.hkStore }

    private let type = HKCategoryType(.mindfulSession)

    /// Вызывается после того, как диалог разрешений закрыт (или уже не нужен).
    var onAuthorizationFinished: () -> Void = {}

    /// Спросить разрешение (запись mindful + чтение типов выгрузки), только если есть что спросить —
    /// в том числе у тех, кто раньше разрешил одну запись mindful.
    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [type]
        let read = HealthTypes.readTypes
        let store = self.store
        let done = onAuthorizationFinished
        store.getRequestStatusForAuthorization(toShare: share, read: read) { status, _ in
            guard status == .shouldRequest else { return }
            store.requestAuthorization(toShare: share, read: read) { _, _ in
                DispatchQueue.main.async { done() }
            }
        }
    }

    /// Старт таймера: спросить только в самый первый раз (как раньше для mindful). Потом — кнопка «Connect Health».
    func requestOnFirstUse() {
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: type) == .notDetermined else { return }
        requestAuthorizationIfNeeded()
    }

    /// Только пишет, если разрешение уже выдано.
    func saveMindful(start: Date, end: Date) {
        guard HKHealthStore.isHealthDataAvailable(), end > start,
              store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let type = self.type
        let store = self.store
        Task.detached {
            do {
                let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                              start: start, end: end)
                try await store.save(sample)
            } catch {
                // молча
            }
        }
    }
}

/// Типы HealthKit для выгрузки: ключ Life → тип и единица.
enum HealthTypes {
    struct Quantity {
        let key: String
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
    }

    static let perMinute = HKUnit.count().unitDivided(by: .minute())

    static let quantities: [Quantity] = [
        .init(key: "steps", id: .stepCount, unit: .count()),
        .init(key: "distance", id: .distanceWalkingRunning, unit: .meterUnit(with: .kilo)),
        .init(key: "flights", id: .flightsClimbed, unit: .count()),
        .init(key: "active", id: .activeEnergyBurned, unit: .kilocalorie()),
        .init(key: "basal", id: .basalEnergyBurned, unit: .kilocalorie()),
        .init(key: "weight", id: .bodyMass, unit: .gramUnit(with: .kilo)),
        .init(key: "fat", id: .bodyFatPercentage, unit: .percent()),
        .init(key: "bmi", id: .bodyMassIndex, unit: .count()),
        .init(key: "lean", id: .leanBodyMass, unit: .gramUnit(with: .kilo)),
        .init(key: "speed", id: .walkingSpeed, unit: HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour())),
        .init(key: "steplen", id: .walkingStepLength, unit: .meterUnit(with: .centi)),
        .init(key: "support", id: .walkingDoubleSupportPercentage, unit: .percent()),
        .init(key: "asym", id: .walkingAsymmetryPercentage, unit: .percent()),
        .init(key: "steadiness", id: .appleWalkingSteadiness, unit: .percent()),
        .init(key: "headphones", id: .headphoneAudioExposure, unit: .decibelAWeightedSoundPressureLevel()),
        .init(key: "resthr", id: .restingHeartRate, unit: perMinute),
        .init(key: "hrv", id: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)),
        .init(key: "hr", id: .heartRate, unit: perMinute),
        .init(key: "resp", id: .respiratoryRate, unit: perMinute),
        .init(key: "vo2", id: .vo2Max, unit: HKUnit(from: "ml/kg*min")),
    ]

    static let sleep = HKCategoryType(.sleepAnalysis)
    static let mindful = HKCategoryType(.mindfulSession)

    /// Всё, что выгрузка читает (и на что вешаются observer'ы).
    static var sampleTypes: [HKSampleType] {
        quantities.map { HKQuantityType($0.id) } + [sleep, mindful]
    }

    static var readTypes: Set<HKObjectType> { Set(sampleTypes.map { $0 as HKObjectType }) }

    /// Сон, а не «в кровати»/«проснулся».
    static func isAsleep(_ value: Int) -> Bool {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: value) else { return false }
        switch v {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified: return true
        default: return false
        }
    }
}

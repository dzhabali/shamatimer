import Foundation
import HealthKit

/// Запись Mindful Minutes в Apple Health. Разрешение спрашивается при первой записи; ошибки молча.
final class HealthStore {
    private let store = HKHealthStore()

    private let type = HKCategoryType(.mindfulSession)

    /// Спросить разрешение один раз, на переднем плане (первый старт таймера / после входа).
    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: type) == .notDetermined else { return }
        store.requestAuthorization(toShare: [type], read: []) { _, _ in }
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

import Foundation

public protocol LaunchServicesClient: Sendable {
    /// `lsregister -u <app>` — usuwa wpis bundla z bazy LaunchServices.
    /// Wywoływane PRZED skasowaniem `.app` z dysku.
    func unregister(app: URL)

    /// `lsregister -gc` + `-r -f -domain ...` — pełna przebudowa bazy.
    /// Drogie (~kilka sekund). Wywoływać RAZ po całym batchu uninstalla.
    func rebuild()
}

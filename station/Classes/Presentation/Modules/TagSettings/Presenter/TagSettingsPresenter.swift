// swiftlint:disable file_length
import Foundation
import RealmSwift
import BTKit
import UIKit

class TagSettingsPresenter: NSObject, TagSettingsModuleInput {
    weak var view: TagSettingsViewInput!
    var router: TagSettingsRouterInput!
    var backgroundPersistence: BackgroundPersistence!
    var ruuviTagService: RuuviTagService!
    var errorPresenter: ErrorPresenter!
    var photoPickerPresenter: PhotoPickerPresenter! { didSet { photoPickerPresenter.delegate = self  } }
    var foreground: BTForeground!
    var background: BTBackground!
    var calibrationService: CalibrationService!
    var alertService: AlertService!
    var settings: Settings!
    var connectionPersistence: ConnectionPersistence!
    var pushNotificationsManager: PushNotificationsManager!
    var permissionPresenter: PermissionPresenter!

    private var ruuviTag: RuuviTagRealm! { didSet { syncViewModel() } }
    private var humidity: Double? { didSet { viewModel.relativeHumidity.value = humidity } }
    private var viewModel: TagSettingsViewModel! { didSet { view.viewModel = viewModel } }
    private var ruuviTagToken: NotificationToken?
    private var advertisementToken: ObservationToken?
    private var heartbeatToken: ObservationToken?
    private var temperatureUnitToken: NSObjectProtocol?
    private var humidityUnitToken: NSObjectProtocol?
    private var connectToken: NSObjectProtocol?
    private var disconnectToken: NSObjectProtocol?
    private var appDidBecomeActiveToken: NSObjectProtocol?
    private var alertDidChangeToken: NSObjectProtocol?

    deinit {
        ruuviTagToken?.invalidate()
        advertisementToken?.invalidate()
        heartbeatToken?.invalidate()
        if let temperatureUnitToken = temperatureUnitToken {
            NotificationCenter.default.removeObserver(temperatureUnitToken)
        }
        if let humidityUnitToken = humidityUnitToken {
            NotificationCenter.default.removeObserver(humidityUnitToken)
        }
        if let connectToken = connectToken {
            NotificationCenter.default.removeObserver(connectToken)
        }
        if let disconnectToken = disconnectToken {
            NotificationCenter.default.removeObserver(disconnectToken)
        }
        if let appDidBecomeActiveToken = appDidBecomeActiveToken {
            NotificationCenter.default.removeObserver(appDidBecomeActiveToken)
        }
        if let alertDidChangeToken = alertDidChangeToken {
            NotificationCenter.default.removeObserver(alertDidChangeToken)
        }
    }

    func configure(ruuviTag: RuuviTagRealm, humidity: Double?) {
        self.viewModel = TagSettingsViewModel()
        self.ruuviTag = ruuviTag
        self.humidity = humidity
        bindViewModel(to: ruuviTag)
        startObservingRuuviTag()
        startScanningRuuviTag()
        startObservingSettingsChanges()
        startObservingConnectionStatus()
        startObservingApplicationState()
        startObservingAlertChanges()
    }
}

// MARK: - TagSettingsViewOutput
extension TagSettingsPresenter: TagSettingsViewOutput {

    func viewWillAppear() {
        checkPushNotificationsStatus()
    }

    func viewDidAskToDismiss() {
        router.dismiss()
    }

    func viewDidAskToRandomizeBackground() {
        viewModel.background.value = backgroundPersistence.setNextDefaultBackground(for: ruuviTag.uuid)
    }

    func viewDidAskToRemoveRuuviTag() {
        view.showTagRemovalConfirmationDialog()
    }

    func viewDidConfirmTagRemoval() {
        let operation = ruuviTagService.delete(ruuviTag: ruuviTag)
        operation.on(success: { [weak self] _ in
            self?.router.dismiss()
        }, failure: { [weak self] (error) in
            self?.errorPresenter.present(error: error)
        })
    }

    func viewDidChangeTag(name: String) {
        let finalName = name.isEmpty ? (ruuviTag.mac ?? ruuviTag.uuid) : name
        let operation = ruuviTagService.update(name: finalName, of: ruuviTag)
        operation.on(failure: { [weak self] (error) in
            self?.errorPresenter.present(error: error)
        })
    }

    func viewDidAskToCalibrateHumidity() {
        if let humidity = humidity {
            router.openHumidityCalibration(ruuviTag: ruuviTag, humidity: humidity)
        }
    }

    func viewDidAskToSelectBackground(sourceView: UIView) {
        photoPickerPresenter.pick(sourceView: sourceView)
    }

    func viewDidTapOnMacAddress() {
        if viewModel.mac.value != nil {
            view.showMacAddressDetail()
        } else {
            view.showUpdateFirmwareDialog()
        }
    }

    func viewDidTapOnUUID() {
        view.showUUIDDetail()
    }

    func viewDidAskToLearnMoreAboutFirmwareUpdate() {
        UIApplication.shared.open(URL(string: "https://lab.ruuvi.com/dfu")!)
    }

    func viewDidTapOnTxPower() {
        if viewModel.txPower.value == nil {
            view.showUpdateFirmwareDialog()
        }
    }

    func viewDidTapOnMovementCounter() {
        if viewModel.movementCounter.value == nil {
            view.showUpdateFirmwareDialog()
        }
    }

    func viewDidTapOnMeasurementSequenceNumber() {
        if viewModel.measurementSequenceNumber.value == nil {
            view.showUpdateFirmwareDialog()
        }
    }

    func viewDidTapOnNoValuesView() {
        view.showUpdateFirmwareDialog()
    }

    func viewDidTapOnHumidityAccessoryButton() {
        view.showHumidityIsClippedDialog()
    }

    func viewDidAskToFixHumidityAdjustment() {
        if let humidity = humidity {
            let operation = calibrationService.calibrateHumidityTo100Percent(currentValue: humidity, for: ruuviTag)
            operation.on(failure: { [weak self] (error) in
                self?.errorPresenter.present(error: error)
            })
        }
    }

    func viewDidTapOnAlertsDisabledView() {
        let isPN = viewModel.isPushNotificationsEnabled.value ?? false
        let isCo = viewModel.isConnected.value ?? false

        if !isPN && !isCo {
            view.showBothNotConnectedAndNoPNPermissionDialog()
        } else if !isPN {
            permissionPresenter.presentNoPushNotificationsPermission()
        } else if !isCo {
            view.showNotConnectedDialog()
        }
    }

    func viewDidAskToConnectFromAlertsDisabledDialog() {
        viewModel?.keepConnection.value = true
    }
}

// MARK: - PhotoPickerPresenterDelegate
extension TagSettingsPresenter: PhotoPickerPresenterDelegate {
    func photoPicker(presenter: PhotoPickerPresenter, didPick photo: UIImage) {
        let set = backgroundPersistence.setCustomBackground(image: photo, for: ruuviTag.uuid)
        set.on(success: { [weak self] _ in
            self?.viewModel.background.value = photo
        }, failure: { [weak self] (error) in
            self?.errorPresenter.present(error: error)
        })
    }
}

// MARK: - Private
extension TagSettingsPresenter {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func syncViewModel() {
        viewModel.temperatureUnit.value = settings.temperatureUnit
        viewModel.humidityUnit.value = settings.humidityUnit
        viewModel.isConnected.value = background.isConnected(uuid: ruuviTag.uuid)
        viewModel.temperatureAlertDescription.value = alertService.temperatureDescription(for: ruuviTag.uuid)
        viewModel.relativeHumidityAlertDescription.value = alertService.relativeHumidityDescription(for: ruuviTag.uuid)
        viewModel.absoluteHumidityAlertDescription.value = alertService.absoluteHumidityDescription(for: ruuviTag.uuid)
        viewModel.dewPointAlertDescription.value = alertService.dewPointDescription(for: ruuviTag.uuid)
        viewModel.pressureAlertDescription.value = alertService.pressureDescription(for: ruuviTag.uuid)
        viewModel.connectionAlertDescription.value = alertService.connectionDescription(for: ruuviTag.uuid)
        viewModel.movementAlertDescription.value = alertService.movementDescription(for: ruuviTag.uuid)

        viewModel.background.value = backgroundPersistence.background(for: ruuviTag.uuid)

        if ruuviTag.name == ruuviTag.uuid || ruuviTag.name == ruuviTag.mac {
            viewModel.name.value = nil
        } else {
            viewModel.name.value = ruuviTag.name
        }

        viewModel.isConnectable.value = ruuviTag.isConnectable
        viewModel.isConnected.value = background.isConnected(uuid: ruuviTag.uuid)
        viewModel.keepConnection.value = connectionPersistence.keepConnection(to: ruuviTag.uuid)

        viewModel.mac.value = ruuviTag.mac
        viewModel.uuid.value = ruuviTag.uuid
        viewModel.version.value = ruuviTag.version

        viewModel.relativeHumidity.value = humidity
        viewModel.humidityOffset.value = ruuviTag.humidityOffset
        viewModel.humidityOffsetDate.value = ruuviTag.humidityOffsetDate

        viewModel.relativeHumidity.value = ruuviTag.data.last?.humidity.value

        viewModel.voltage.value = ruuviTag.data.last?.voltage.value
        viewModel.accelerationX.value = ruuviTag.data.last?.accelerationX.value
        viewModel.accelerationY.value = ruuviTag.data.last?.accelerationY.value
        viewModel.accelerationZ.value = ruuviTag.data.last?.accelerationZ.value

        // version 5 supports mc, msn, txPower
        if ruuviTag.version == 5 {
            viewModel.movementCounter.value = ruuviTag.data
                .last(where: { $0.movementCounter.value != nil })?.movementCounter.value
            viewModel.measurementSequenceNumber.value = ruuviTag.data
                .last(where: { $0.measurementSequenceNumber.value != nil })?.measurementSequenceNumber.value
            viewModel.txPower.value = ruuviTag.data.last(where: { $0.txPower.value != nil })?.txPower.value
        } else {
            viewModel.movementCounter.value = nil
            viewModel.measurementSequenceNumber.value = nil
            viewModel.txPower.value = nil
        }

        AlertType.allCases.forEach { (type) in
            switch type {
            case .temperature:
                if case .temperature(let lower, let upper) = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isTemperatureAlertOn.value = true
                    viewModel.celsiusLowerBound.value = lower
                    viewModel.celsiusUpperBound.value = upper
                } else {
                    viewModel.isTemperatureAlertOn.value = false
                    if let celsiusLower = alertService.lowerCelsius(for: ruuviTag.uuid) {
                        viewModel.celsiusLowerBound.value = celsiusLower
                    }
                    if let celsiusUpper = alertService.upperCelsius(for: ruuviTag.uuid) {
                        viewModel.celsiusUpperBound.value = celsiusUpper
                    }
                }
            case .relativeHumidity:
                if case .relativeHumidity(let lower, let upper) = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isRelativeHumidityAlertOn.value = true
                    viewModel.relativeHumidityLowerBound.value = lower
                    viewModel.relativeHumidityUpperBound.value = upper
                } else {
                    viewModel.isRelativeHumidityAlertOn.value = false
                    if let realtiveHumidityLower = alertService.lowerRelativeHumidity(for: ruuviTag.uuid) {
                        viewModel.relativeHumidityLowerBound.value = realtiveHumidityLower
                    }
                    if let relativeHumidityUpper = alertService.upperRelativeHumidity(for: ruuviTag.uuid) {
                        viewModel.relativeHumidityUpperBound.value = relativeHumidityUpper
                    }
                }
            case .absoluteHumidity:
                if case .absoluteHumidity(let lower, let upper) = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isAbsoluteHumidityAlertOn.value = true
                    viewModel.absoluteHumidityLowerBound.value = lower
                    viewModel.absoluteHumidityUpperBound.value = upper
                } else {
                    viewModel.isAbsoluteHumidityAlertOn.value = false
                    if let absoluteHumidityLower = alertService.lowerAbsoluteHumidity(for: ruuviTag.uuid) {
                        viewModel.absoluteHumidityLowerBound.value = absoluteHumidityLower
                    }
                    if let absoluteHumidityUpper = alertService.upperAbsoluteHumidity(for: ruuviTag.uuid) {
                        viewModel.absoluteHumidityUpperBound.value = absoluteHumidityUpper
                    }
                }
            case .dewPoint:
                if case .dewPoint(let lower, let upper) = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isDewPointAlertOn.value = true
                    viewModel.dewPointCelsiusLowerBound.value = lower
                    viewModel.dewPointCelsiusUpperBound.value = upper
                } else {
                    viewModel.isDewPointAlertOn.value = false
                    if let dewPointCelsiusLowerBound = alertService.lowerDewPointCelsius(for: ruuviTag.uuid) {
                        viewModel.dewPointCelsiusLowerBound.value = dewPointCelsiusLowerBound
                    }
                    if let dewPointCelsiusUpperBound = alertService.upperDewPointCelsius(for: ruuviTag.uuid) {
                        viewModel.dewPointCelsiusUpperBound.value = dewPointCelsiusUpperBound
                    }
                }
            case .pressure:
                if case .pressure(let lower, let upper) = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isPressureAlertOn.value = true
                    viewModel.pressureLowerBound.value = lower
                    viewModel.pressureUpperBound.value = upper
                } else {
                    viewModel.isPressureAlertOn.value = false
                    if let pressureLowerBound = alertService.lowerPressure(for: ruuviTag.uuid) {
                        viewModel.pressureLowerBound.value = pressureLowerBound
                    }
                    if let pressureUpperBound = alertService.upperPressure(for: ruuviTag.uuid) {
                        viewModel.pressureUpperBound.value = pressureUpperBound
                    }
                }
            case .connection:
                if case .connection = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isConnectionAlertOn.value = true
                } else {
                    viewModel.isConnectionAlertOn.value = false
                }
            case .movement:
                if case .movement = alertService.alert(for: ruuviTag.uuid, of: type) {
                    viewModel.isMovementAlertOn.value = true
                } else {
                    viewModel.isMovementAlertOn.value = false
                }
            }
        }
    }

    private func startObservingRuuviTag() {
        ruuviTagToken?.invalidate()
        ruuviTagToken = ruuviTag.observe { [weak self] (change) in
            switch change {
            case .change:
                self?.syncViewModel()
            case .deleted:
                self?.router.dismiss()
            case .error(let error):
                self?.errorPresenter.present(error: error)
            }
        }
    }

    private func startScanningRuuviTag() {
        advertisementToken?.invalidate()
        advertisementToken = foreground.observe(self, uuid: ruuviTag.uuid, closure: { [weak self] (_, device) in
            if let tag = device.ruuvi?.tag {
                self?.sync(device: tag)
            }
        })
        heartbeatToken?.invalidate()
        heartbeatToken = background.observe(self, uuid: ruuviTag.uuid, closure: { [weak self] (_, device) in
            if let tag = device.ruuvi?.tag {
                self?.sync(device: tag)
            }
        })
    }

    private func sync(device: RuuviTag) {
        humidity = device.humidity
        viewModel.voltage.value = device.voltage
        viewModel.accelerationX.value = device.accelerationX
        viewModel.accelerationY.value = device.accelerationY
        viewModel.accelerationZ.value = device.accelerationZ
        if viewModel.version.value != device.version {
            viewModel.version.value = device.version
        }
        if viewModel.isConnectable.value != device.isConnectable {
            viewModel.isConnectable.value = device.isConnectable
        }
        viewModel.movementCounter.value = device.movementCounter
        viewModel.measurementSequenceNumber.value = device.measurementSequenceNumber
        viewModel.txPower.value = device.txPower
        if viewModel.isConnected.value != device.isConnected {
            viewModel.isConnected.value = device.isConnected
        }

        if let mac = device.mac {
            viewModel.mac.value = mac
        }
    }
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func bindViewModel(to ruuviTag: RuuviTagRealm) {
        bind(viewModel.keepConnection, fire: false) { observer, keepConnection in
            observer.connectionPersistence.setKeepConnection(keepConnection.bound, for: ruuviTag.uuid)
        }

        // temperature alert
        let temperatureLower = viewModel.celsiusLowerBound
        let temperatureUpper = viewModel.celsiusUpperBound
        bind(viewModel.isTemperatureAlertOn, fire: false) {
            [weak temperatureLower, weak temperatureUpper] observer, isOn in
            if let l = temperatureLower?.value, let u = temperatureUpper?.value {
                let type: AlertType = .temperature(lower: l, upper: u)
                let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
                if currentState != isOn.bound {
                    if isOn.bound {
                        observer.alertService.register(type: type, for: ruuviTag.uuid)
                    } else {
                        observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                    }
                }
            }
        }
        bind(viewModel.celsiusLowerBound, fire: false) { observer, lower in
            observer.alertService.setLower(celsius: lower, for: ruuviTag.uuid)
        }
        bind(viewModel.celsiusUpperBound, fire: false) { observer, upper in
            observer.alertService.setUpper(celsius: upper, for: ruuviTag.uuid)
        }
        bind(viewModel.temperatureAlertDescription, fire: false) {observer, temperatureAlertDescription in
            observer.alertService.setTemperature(description: temperatureAlertDescription, for: ruuviTag.uuid)
        }

        // relative humidity alert
        let relativeHumidityLower = viewModel.relativeHumidityLowerBound
        let relativeHumidityUpper = viewModel.relativeHumidityUpperBound
        bind(viewModel.isRelativeHumidityAlertOn, fire: false) {
            [weak relativeHumidityLower, weak relativeHumidityUpper] observer, isOn in
            if let l = relativeHumidityLower?.value, let u = relativeHumidityUpper?.value {
                let type: AlertType = .relativeHumidity(lower: l, upper: u)
                let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
                if currentState != isOn.bound {
                    if isOn.bound {
                        observer.alertService.register(type: type, for: ruuviTag.uuid)
                    } else {
                        observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                    }
                }
            }
        }
        bind(viewModel.relativeHumidityLowerBound, fire: false) { observer, lower in
            observer.alertService.setLower(relativeHumidity: lower, for: ruuviTag.uuid)
        }
        bind(viewModel.relativeHumidityUpperBound, fire: false) { observer, upper in
            observer.alertService.setUpper(relativeHumidity: upper, for: ruuviTag.uuid)
        }
        bind(viewModel.relativeHumidityAlertDescription, fire: false) { observer, relativeHumidityAlertDescription in
            observer.alertService.setRelativeHumidity(description: relativeHumidityAlertDescription, for: ruuviTag.uuid)
        }

        // absolute humidity alert
        let absoluteHumidityLower = viewModel.absoluteHumidityLowerBound
        let absoluteHumidityUpper = viewModel.absoluteHumidityUpperBound
        bind(viewModel.isAbsoluteHumidityAlertOn, fire: false) {
            [weak absoluteHumidityLower, weak absoluteHumidityUpper] observer, isOn in
            if let l = absoluteHumidityLower?.value, let u = absoluteHumidityUpper?.value {
                let type: AlertType = .absoluteHumidity(lower: l, upper: u)
                let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
                if currentState != isOn.bound {
                    if isOn.bound {
                        observer.alertService.register(type: type, for: ruuviTag.uuid)
                    } else {
                        observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                    }
                }
            }
        }

        bind(viewModel.absoluteHumidityLowerBound, fire: false) { observer, lower in
            observer.alertService.setLower(absoluteHumidity: lower, for: ruuviTag.uuid)
        }

        bind(viewModel.absoluteHumidityUpperBound, fire: false) { observer, upper in
            observer.alertService.setUpper(absoluteHumidity: upper, for: ruuviTag.uuid)
        }

        bind(viewModel.absoluteHumidityAlertDescription, fire: false) { observer, absoluteHumidityAlertDescription in
            observer.alertService.setAbsoluteHumidity(description: absoluteHumidityAlertDescription, for: ruuviTag.uuid)
        }

        // dew point alert
        let dewPointLower = viewModel.dewPointCelsiusLowerBound
        let dewPointUpper = viewModel.dewPointCelsiusUpperBound
        bind(viewModel.isDewPointAlertOn, fire: false) {
            [weak dewPointLower, weak dewPointUpper] observer, isOn in
            if let l = dewPointLower?.value, let u = dewPointUpper?.value {
                let type: AlertType = .dewPoint(lower: l, upper: u)
                let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
                if currentState != isOn.bound {
                    if isOn.bound {
                        observer.alertService.register(type: type, for: ruuviTag.uuid)
                    } else {
                        observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                    }
                }
            }
        }
        bind(viewModel.dewPointCelsiusLowerBound, fire: false) { observer, lower in
            observer.alertService.setLowerDewPoint(celsius: lower, for: ruuviTag.uuid)
        }
        bind(viewModel.dewPointCelsiusUpperBound, fire: false) { observer, upper in
            observer.alertService.setUpperDewPoint(celsius: upper, for: ruuviTag.uuid)
        }
        bind(viewModel.dewPointAlertDescription, fire: false) { observer, dewPointAlertDescription in
            observer.alertService.setDewPoint(description: dewPointAlertDescription, for: ruuviTag.uuid)
        }

        // pressure
        let pressureLower = viewModel.pressureLowerBound
        let pressureUpper = viewModel.pressureUpperBound
        bind(viewModel.isPressureAlertOn, fire: false) {
            [weak pressureLower, weak pressureUpper] observer, isOn in
            if let l = pressureLower?.value, let u = pressureUpper?.value {
                let type: AlertType = .pressure(lower: l, upper: u)
                let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
                if currentState != isOn.bound {
                    if isOn.bound {
                        observer.alertService.register(type: type, for: ruuviTag.uuid)
                    } else {
                        observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                    }
                }
            }
        }

        bind(viewModel.pressureLowerBound, fire: false) { observer, lower in
            observer.alertService.setLower(pressure: lower, for: ruuviTag.uuid)
        }

        bind(viewModel.pressureUpperBound, fire: false) { observer, upper in
            observer.alertService.setUpper(pressure: upper, for: ruuviTag.uuid)
        }

        bind(viewModel.pressureAlertDescription, fire: false) { observer, pressureAlertDescription in
            observer.alertService.setPressure(description: pressureAlertDescription, for: ruuviTag.uuid)
        }

        // connection
        bind(viewModel.isConnectionAlertOn, fire: false) { observer, isOn in
            let type: AlertType = .connection
            let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
            if currentState != isOn.bound {
                if isOn.bound {
                    observer.alertService.register(type: type, for: ruuviTag.uuid)
                } else {
                    observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                }
            }
        }

        bind(viewModel.connectionAlertDescription, fire: false) { observer, connectionAlertDescription in
            observer.alertService.setConnection(description: connectionAlertDescription, for: ruuviTag.uuid)
        }

        // movement
        bind(viewModel.isMovementAlertOn, fire: false) { observer, isOn in
            let last = ruuviTag.data.sorted(byKeyPath: "date").last?.movementCounter.value ?? 0
            let type: AlertType = .movement(last: last)
            let currentState = observer.alertService.isOn(type: type, for: ruuviTag.uuid)
            if currentState != isOn.bound {
                if isOn.bound {
                    observer.alertService.register(type: type, for: ruuviTag.uuid)
                } else {
                    observer.alertService.unregister(type: type, for: ruuviTag.uuid)
                }
            }
        }

        bind(viewModel.movementAlertDescription, fire: false) { observer, movementAlertDescription in
            observer.alertService.setMovement(description: movementAlertDescription, for: ruuviTag.uuid)
        }
    }

    private func startObservingSettingsChanges() {
        temperatureUnitToken = NotificationCenter
            .default
            .addObserver(forName: .TemperatureUnitDidChange,
                         object: nil,
                         queue: .main) { [weak self] _ in
            self?.viewModel.temperatureUnit.value = self?.settings.temperatureUnit
        }
        humidityUnitToken = NotificationCenter
            .default
            .addObserver(forName: .HumidityUnitDidChange,
                         object: nil,
                         queue: .main,
                         using: { [weak self] _ in
            self?.viewModel.humidityUnit.value = self?.settings.humidityUnit
        })
    }

    private func startObservingConnectionStatus() {
        connectToken = NotificationCenter
            .default
            .addObserver(forName: .BTBackgroundDidConnect,
                         object: nil,
                         queue: .main,
                         using: { [weak self] (notification) in
            if let userInfo = notification.userInfo,
                let uuid = userInfo[BTBackgroundDidConnectKey.uuid] as? String,
                uuid == self?.ruuviTag.uuid {
                self?.viewModel.isConnected.value = true
            }
        })

        disconnectToken = NotificationCenter
            .default
            .addObserver(forName: .BTBackgroundDidDisconnect,
                         object: nil,
                         queue: .main,
                         using: { [weak self] (notification) in
            if let userInfo = notification.userInfo,
                let uuid = userInfo[BTBackgroundDidDisconnectKey.uuid] as? String,
                !(self?.ruuviTag.isInvalidated ?? true)
                && uuid == self?.ruuviTag.uuid  {
                self?.viewModel.isConnected.value = false
            }
        })
    }

    private func startObservingApplicationState() {
        appDidBecomeActiveToken = NotificationCenter
            .default
            .addObserver(forName: UIApplication.didBecomeActiveNotification,
                         object: nil,
                         queue: .main,
                         using: { [weak self] (_) in
            self?.checkPushNotificationsStatus()
        })
    }

    private func checkPushNotificationsStatus() {
        pushNotificationsManager.getRemoteNotificationsAuthorizationStatus { [weak self] (status) in
            switch status {
            case .notDetermined:
                self?.pushNotificationsManager.registerForRemoteNotifications()
            case .authorized:
                self?.viewModel.isPushNotificationsEnabled.value = true
            case .denied:
                self?.viewModel.isPushNotificationsEnabled.value = false
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func startObservingAlertChanges() {
        alertDidChangeToken = NotificationCenter
            .default
            .addObserver(forName: .AlertServiceAlertDidChange,
                         object: nil,
                         queue: .main,
                         using: { [weak self] (notification) in
            if let userInfo = notification.userInfo,
                let uuid = userInfo[AlertServiceAlertDidChangeKey.uuid] as? String,
                uuid == self?.viewModel.uuid.value,
                let type = userInfo[AlertServiceAlertDidChangeKey.type] as? AlertType {
                    switch type {
                    case .temperature:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isTemperatureAlertOn.value {
                            self?.viewModel.isTemperatureAlertOn.value = isOn
                        }
                    case .relativeHumidity:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isRelativeHumidityAlertOn.value {
                            self?.viewModel.isRelativeHumidityAlertOn.value = isOn
                        }
                    case .absoluteHumidity:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isAbsoluteHumidityAlertOn.value {
                            self?.viewModel.isAbsoluteHumidityAlertOn.value = isOn
                        }
                    case .dewPoint:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isDewPointAlertOn.value {
                            self?.viewModel.isDewPointAlertOn.value = isOn
                        }
                    case .pressure:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isPressureAlertOn.value {
                            self?.viewModel.isPressureAlertOn.value = isOn
                        }
                    case .connection:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isConnectionAlertOn.value {
                            self?.viewModel.isConnectionAlertOn.value = isOn
                        }
                    case .movement:
                        let isOn = self?.alertService.isOn(type: type, for: uuid)
                        if isOn != self?.viewModel.isMovementAlertOn.value {
                            self?.viewModel.isMovementAlertOn.value = isOn
                        }
                    }
            }
        })
    }
}
// swiftlint:enable file_length

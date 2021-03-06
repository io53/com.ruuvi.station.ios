import LightRoute

class TagSettingsRouter: TagSettingsRouterInput {
    weak var transitionHandler: TransitionHandler!

    // swiftlint:disable weak_delegate
    private lazy var humidityCalibrationTransitioningDelegate = HumidityCalibrationTransitioningDelegate()
    // swiftlint:enable weak_delegate

    func dismiss() {
        try! transitionHandler.closeCurrentModule().perform()
    }

    func openHumidityCalibration(ruuviTag: RuuviTagRealm, humidity: Double) {
        let factory = StoryboardFactory(storyboardName: "HumidityCalibration")
        try! transitionHandler
            .forStoryboard(factory: factory, to: HumidityCalibrationModuleInput.self)
            .add(transitioningDelegate: humidityCalibrationTransitioningDelegate)
            .apply(to: { (viewController) in
                viewController.modalPresentationStyle = .custom
            })
            .then({ (module) -> Any? in
                module.configure(ruuviTag: ruuviTag, humidity: humidity)
            })
    }
}

import UIKit
import RealmSwift
import BTKit

class DashboardScrollViewController: UIViewController {
    var output: DashboardViewOutput!
    
    @IBOutlet weak var settingsButton: UIBarButtonItem!
    @IBOutlet weak var scrollView: UIScrollView!
    
    var temperatureUnit: TemperatureUnit = .celsius { didSet { updateUITemperatureUnit() } }
    var ruuviTags: Results<RuuviTagRealm>? { didSet { updateUIRuuviTags() }  }
    
    private var ruuviTagViews = [RuuviTagRealm: DashboardRuuviTagView]()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

// MARK: - DashboardViewInput
extension DashboardScrollViewController: DashboardViewInput {
    func localize() {
        
    }
    
    func apply(theme: Theme) {
        
    }
    
    func update(ruuviTag: RuuviTagRealm, with data: RuuviTag) {
        if let view = ruuviTagViews[ruuviTag] {
            configure(view: view, with: data)
        }
    }
}

// MARK: - IBActions
extension DashboardScrollViewController {
    @IBAction func settingsButtonTouchUpInside(_ sender: UIButton) {
        
    }
    
    @IBAction func menuButtonTouchUpInside(_ sender: Any) {
        output.viewDidTriggerMenu()
    }
}

// MARK: - View lifecycle
extension DashboardScrollViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        updateUI()
        output.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        output.viewWillAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        output.viewWillDisappear()
    }
}

// MARK: - Configure view
extension DashboardScrollViewController {
    private func configure(view: DashboardRuuviTagView, with data: RuuviTag) {
        switch temperatureUnit {
        case .celsius:
            view.temperatureLabel.text = String(format: "%.2f", data.celsius)
            view.temperatureUnitLabel.text = "°C"
        case .fahrenheit:
            view.temperatureLabel.text = String(format: "%.2f", data.fahrenheit)
            view.temperatureUnitLabel.text = "°C"
        }
        view.humidityLabel.text = String(format: "%.2f", data.humidity) + " %"
        view.pressureLabel.text = "\(data.pressure) hPa"
        view.rssiLabel.text = "\(data.rssi) dBm"
        view.updatedAt = Date()
    }
    
    private func configure(view: DashboardRuuviTagView, with ruuviTag: RuuviTagRealm) {
        view.nameLabel.text = ruuviTag.name.uppercased()
        configureTemperature(view: view, with: ruuviTag)
        if let data = ruuviTag.data.last {
            view.humidityLabel.text = String(format: "%.2f", data.humidity) + " %"
            view.pressureLabel.text = "\(data.pressure) hPa"
            view.rssiLabel.text = "\(data.rssi) dBm"
        }
    }
    
    private func configureTemperature(view: DashboardRuuviTagView, with ruuviTag: RuuviTagRealm) {
        if let data = ruuviTag.data.last {
            switch temperatureUnit {
            case .celsius:
                view.temperatureLabel.text = String(format: "%.2f", data.celsius)
                view.temperatureUnitLabel.text = "°C"
            case .fahrenheit:
                view.temperatureLabel.text = String(format: "%.2f", data.fahrenheit)
                view.temperatureUnitLabel.text = "°C"
            }
        }
    }
}

// MARK: - Update UI
extension DashboardScrollViewController {
    private func updateUI() {
        updateUITemperatureUnit()
        updateUIRuuviTags()
    }
    
    private func updateUITemperatureUnit() {
        if isViewLoaded {
            ruuviTagViews.forEach({ configureTemperature(view: $1, with: $0) })
        }
    }
    
    private func updateUIRuuviTags() {
        if isViewLoaded {
            ruuviTagViews.values.forEach({ $0.removeFromSuperview() })
            
            if let ruuviTags = ruuviTags, ruuviTags.count > 0 {
                var leftView: UIView = scrollView
                for ruuviTag in ruuviTags {
                    let view = Bundle.main.loadNibNamed("DashboardRuuviTagView", owner: self, options: nil)?.first as! DashboardRuuviTagView
                    view.translatesAutoresizingMaskIntoConstraints = false
                    scrollView.addSubview(view)
                    position(view, leftView)
                    configure(view: view, with: ruuviTag)
                    ruuviTagViews[ruuviTag] = view
                    leftView = view
                }
                scrollView.addConstraint(NSLayoutConstraint(item: leftView, attribute: .trailing, relatedBy: .equal
                    , toItem: scrollView, attribute: .trailing, multiplier: 1.0, constant: 0.0))
            }
        }
    }
    
    private func position(_ view: DashboardRuuviTagView, _ leftView: UIView) {
        scrollView.addConstraint(NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .equal, toItem: leftView, attribute: leftView == scrollView ? .leading : .trailing, multiplier: 1.0, constant: 0.0))
        scrollView.addConstraint(NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: scrollView, attribute: .top, multiplier: 1.0, constant: 0.0))
        scrollView.addConstraint(NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1.0, constant: 0.0))
        scrollView.addConstraint(NSLayoutConstraint(item: view, attribute: .width, relatedBy: .equal, toItem: scrollView, attribute: .width, multiplier: 1.0, constant: 0.0))
        scrollView.addConstraint(NSLayoutConstraint(item: view, attribute: .height, relatedBy: .equal, toItem: scrollView, attribute: .height, multiplier: 1.0, constant: 0.0))
    }
}
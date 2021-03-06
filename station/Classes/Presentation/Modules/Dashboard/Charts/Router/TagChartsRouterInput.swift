import Foundation

protocol TagChartsRouterInput {
    func dismiss()
    func openDiscover(output: DiscoverModuleOutput)
    func openSettings()
    func openAbout()
    func openRuuviWebsite()
    func openMenu(output: MenuModuleOutput)
    func openTagSettings(ruuviTag: RuuviTagRealm, humidity: Double?)
    func openWebTagSettings(webTag: WebTagRealm)
}

import WidgetKit
import SwiftUI

@main
struct AirPanelWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeviceInfoWidget()
        SMSWidget()
        CallsWidget()
        QuickCommandWidget()
    }
}

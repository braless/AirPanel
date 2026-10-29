import WidgetKit
import SwiftUI

// MARK: - 小组件入口
//
// 经典 TimelineProvider 多小组件方案：拆成 4 个独立 Widget
// （设备 / 通话 / 短信 / 统计），用户在小组件库里按需添加。
// 相比 AppIntent 单 Widget，经典方式在侧载/自签环境下渲染更稳。

@main
struct AirPanelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DeviceWidget()
        CallsWidget()
        SmsWidget()
        StatsWidget()
    }
}

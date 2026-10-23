import WidgetKit
import SwiftUI

// MARK: - 小组件入口
//
// 一个 Widget 配置覆盖全部四种内容：用户长按桌面 →「编辑小组件」，
// 在「显示内容」里选 设备 / 通话 / 短信 / 统计，尺寸在系统的
// 小、中两档之间切。不拆成四个 Widget 是因为四个会占满小组件库，
// 而且用户想换内容时得先删掉再加回来。

@main
struct AirPanelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AirPanelWidget()
    }
}

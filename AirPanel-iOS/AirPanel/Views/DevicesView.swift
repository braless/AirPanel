import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var store: AppStore
    @State private var loading = false
    @State private var errorMsg: String?
    @State private var renamingIMEI: String?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                deviceList
                addCard
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("设备")
        .task { await store.refreshDevices() }
        .refreshable { await store.refreshDevices() }
        .overlay {
            if loading {
                LoadingView(text: "加载设备…")
            } else if let err = errorMsg {
                ErrorView(message: err) { Task { await store.refreshDevices() } }
            }
        }
    }

    var header: some View {
        HStack {
            Text("\(store.devices.count) 台设备 · \(store.devices.filter(\.connected).count) 台在线")
                .font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.55))
            Spacer()
            Button {
                Task { await store.refreshDevices() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.7))
            }
        }
    }

    var deviceList: some View {
        VStack(spacing: 10) {
            if store.devices.isEmpty {
                EmptyState(text: "暂无设备，请确认设备已上线")
            }
            ForEach(store.devices) { d in
                NavigationLink {
                    DeviceDetailView(device: d)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: d.connected ? [Theme.green.opacity(0.5), Theme.green.opacity(0.15)]
                                                                          : [.gray.opacity(0.5), .gray.opacity(0.15)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)
                            Image(systemName: "cpu").font(.system(size: 17)).foregroundColor(Theme.text)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name.isEmpty ? maskedIMEI(d.imei) : d.name)
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                            Text("\(maskedIMEI(d.imei)) · \(maskedPhone(d.phone))")
                                .font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.5))
                        }
                        Spacer()
                        StatusPill(text: d.connected ? "在线" : "离线", color: d.connected ? Theme.green : .gray)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.text.opacity(0.4))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("重命名") { renamingIMEI = d.imei; renameText = d.name }
                    Button("删除", role: .destructive) { Task { await remove(d.imei) } }
                }
            }
        }
    }

    var addCard: some View {
        HStack {
            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
            Text("设备通过 MQTT 上线后自动登记").font(.system(size: 13)).foregroundColor(Theme.text.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    func remove(_ imei: String) async {
        do {
            try await store.api.deleteDevice(imei: imei)
            await store.refreshDevices()
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    @MainActor
    func rename(_ d: Device, to name: String) async {
        do {
            try await store.api.updateDeviceRemark(imei: d.imei, name: name)
            await store.refreshDevices()
        } catch {
            errorMsg = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

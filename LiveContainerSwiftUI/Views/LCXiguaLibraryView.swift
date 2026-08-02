//
//  LCXiguaLibraryView.swift
//  LiveContainerSwiftUI
//
//  西瓜多开自带的应用库。
//
//  上游那套源浏览器(LCSourcesView)让用户自由增删 AltStore 源,和西瓜IPA助手
//  完全重复,已经从 tab 里摘掉了。这里补的是它做不到的那件事:把我们和日后
//  合作方的应用直接装进容器 —— 不签名、不占免费账号那 3 个名额。
//
//  清单不进包,启动时从服务端拉。加一个合作方的应用只要改 lc-apps.json,
//  不用重新发版。
//

import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class XiguaLibraryViewModel: ObservableObject {
    /// 主地址用对外域名(国内更容易连上),连不上退到 Pages 的默认域名。
    /// 两个指向同一个 Cloudflare Pages 项目,内容一样。
    ///
    /// 这里不像西瓜IPA助手那样对域名敏感 —— 商店拿源地址算源的唯一标识,
    /// 换域名会多出一条重复的源;这边是写死的内置清单,缓存按 URL 哈希存,
    /// 换了地址最多是重新拉一次。
    static let sourceURLs: [URL] = [
        URL(string: "https://loveipa.com/lc-apps.json")!,
        URL(string: "https://sideloadstore.pages.dev/lc-apps.json")!,
    ]

    @Published private(set) var source: AltStoreSource?
    @Published private(set) var isLoading = false
    /// 只在有缓存可显示时用作提示条;没有缓存时走整页的错误态。
    @Published private(set) var errorMessage: String?

    private let cacheDirectoryName = "XiguaLibraryCache"

    init() {
        loadCache()
    }

    var apps: [AltStoreSourceApp] {
        source?.apps ?? []
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?
        for url in Self.sourceURLs {
            do {
                let (loaded, data) = try await AltStoreSourceLoader.load(from: url)
                source = loaded
                errorMessage = nil
                storeCache(data)
                return
            } catch {
                lastError = error
            }
        }
        errorMessage = lastError?.localizedDescription ?? "lc.common.error".loc
    }
}

private extension XiguaLibraryViewModel {
    /// 上次拉到的清单。先显示它再联网,离线时这一页也不至于空着。
    func loadCache() {
        guard let fileURL = cacheFileURL(),
              let data = try? Data(contentsOf: fileURL),
              let cached = try? AltStoreSourceLoader.decode(from: data, baseURL: Self.sourceURLs[0])
        else { return }
        source = cached
    }

    func storeCache(_ data: Data) {
        guard let fileURL = cacheFileURL() else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func cacheFileURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = caches.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
            else { return nil }
        }
        return directory.appendingPathComponent("source.json")
    }
}

struct LCXiguaLibraryView: View {
    @StateObject private var viewModel = XiguaLibraryViewModel()
    @EnvironmentObject private var sharedModel: SharedModel

    var body: some View {
        NavigationView {
            Group {
                if viewModel.apps.isEmpty {
                    placeholder
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if let errorMessage = viewModel.errorMessage {
                                staleBanner(errorMessage)
                            }

                            ForEach(viewModel.apps) { app in
                                XiguaLibraryAppBanner(
                                    app: app,
                                    tintFallback: viewModel.source?.tintColor,
                                    installedVersion: installedVersion(of: app),
                                    installAction: install(app:)
                                )
                            }

                            Text("lc.library.footer".loc)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                        .padding()
                    }
                    .refreshable { await viewModel.refresh() }
                }
            }
            .navigationTitle("lc.tabView.library".loc)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("lc.sources.refreshAll".loc, systemImage: "arrow.clockwise") {
                            Task { await viewModel.refresh() }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            // 有缓存时也拉一次:合作方的应用是服务端加的,不刷新就看不到。
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Image(systemName: viewModel.errorMessage == nil ? "square.grid.2x2" : "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text(viewModel.errorMessage ?? "lc.library.empty".loc)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if viewModel.errorMessage != nil {
                    Button("lc.library.retry".loc) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func staleBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("lc.library.staleTitle".loc).font(.footnote).bold()
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    /// 容器里已经装了这个 bundle id 的话,它现在是什么版本。
    private func installedVersion(of app: AltStoreSourceApp) -> String? {
        let installed = sharedModel.apps + sharedModel.hiddenApps
        return installed
            .first { $0.appInfo.bundleIdentifier() == app.bundleIdentifier }?
            .appInfo.version()
    }

    /// 下载和安装都归应用列表那一页管(它有进度条和覆盖安装的处理),
    /// 这里只切过去并把地址递过去。
    @MainActor
    private func install(app: AltStoreSourceApp) {
        guard let downloadURL = app.latestVersion?.downloadURL else { return }
        withAnimation {
            DataManager.shared.model.selectedTab = .apps
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: NSNotification.InstallAppNotification,
                object: ["url": downloadURL]
            )
        }
    }
}

/// 和已安装应用那一栏长得一样(88 高、22 圆角、跟随「动态颜色」设置),
/// 免得同一个应用在两个页面上是两种样子。上游的 LCSourceAppBanner 是
/// private,复用不了。
private struct XiguaLibraryAppBanner: View {
    let app: AltStoreSourceApp
    let tintFallback: Color?
    let installedVersion: String?
    let installAction: (AltStoreSourceApp) -> Void

    @AppStorage("dynamicColors") private var dynamicColors = true
    @Environment(\.colorScheme) private var colorScheme

    private var primaryColor: Color {
        guard dynamicColors else { return Color("FontColor") }
        return app.tintColor ?? tintFallback ?? Color("FontColor")
    }

    private var textColor: Color {
        _ = colorScheme == .dark // 让配色变化触发重绘
        return (dynamicColors ? primaryColor : Color("FontColor")).readableTextColor()
    }

    private var metadataText: String {
        guard let latest = app.latestVersion else { return app.bundleIdentifier }
        var parts = [latest.version]
        if let size = latest.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let subtitle = app.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        } else if let developer = app.developerName, !developer.isEmpty {
            parts.append(developer)
        }
        return parts.joined(separator: " • ")
    }

    /// 已装同一版本就是「已安装」,版本对不上就是「可更新」。
    /// 两种情况按钮都还能点 —— 装同一个 bundle id 时应用列表那边会问是否覆盖。
    private var statusBadge: String? {
        guard let installedVersion else { return nil }
        if installedVersion == app.latestVersion?.version {
            return "lc.library.installed".loc
        }
        return "lc.library.updatable".loc
    }

    var body: some View {
        HStack {
            HStack(alignment: .center, spacing: 12) {
                XiguaLibraryIcon(url: app.iconURL)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(app.name).font(.system(size: 16)).bold()
                        if let statusBadge {
                            Text(statusBadge)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.gray))
                        }
                    }
                    Text(metadataText)
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .lineLimit(2)
                }
            }
            .allowsHitTesting(false)
            Spacer()
            Button {
                installAction(app)
            } label: {
                Text(installedVersion == nil ? "lc.common.install".loc : "lc.library.reinstall".loc)
                    .bold()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(height: 32)
                    .minimumScaleFactor(0.1)
            }
            .buttonStyle(BasicButtonStyle())
            .padding()
            .frame(idealWidth: 70)
            .frame(height: 32)
            .fixedSize()
            .background(Capsule().fill(dynamicColors ? primaryColor : Color("FontColor")))
            .clipShape(Capsule())
        }
        .padding()
        .frame(height: 88)
        .background {
            RoundedRectangle(cornerSize: CGSize(width: 22, height: 22))
                .fill(dynamicColors ? primaryColor.opacity(0.5) : Color("AppBannerBG"))
        }
    }
}

private struct XiguaLibraryIcon: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image("DefaultIcon").resizable().scaledToFill()
    }
}

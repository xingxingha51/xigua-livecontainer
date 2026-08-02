# 西瓜多开

[LiveContainer](https://github.com/LiveContainer/LiveContainer) 的分支,为
[西瓜IPA助手](https://github.com/xingxingha51/xigua-store) 配套定制。

一台设备用免费 Apple 账号最多只能同时装 3 个自签应用。把应用装进这里,
它们共用同一个签名名额 —— 装多少个都只算一个。

## 和上游的差别

**去掉了内置的软件源浏览器。** 上游自带一整套 AltStore 源浏览界面,和
西瓜IPA助手完全重复:同一批应用在两个地方都能装,用户还得判断该用哪个。
装应用的事归商店,这里只负责跑。四个标签页因此变成三个:应用 / 插件 / 设置。

`source://` 深链改为忽略而不是切到已不存在的标签页 —— 加软件源本来也该
由商店处理。

**品牌化。** 显示名「西瓜多开」,绿色图标,界面里提到产品名的中文文案
一并改过。

## 刻意没改的

**Bundle ID 仍是 `com.kdt.livecontainer`。** 签名工具 isideload 靠它做特判
([application.rs](https://github.com/nab138/isideload)),命中后才会注入
`com.kdt.livecontainer.shared` 那一串钥匙串组。改掉 ID,「导入证书」这一步
就会失效。代价是本分支与上游版本互斥,一台设备只能装其中一个。

**`LCAltStoreSourcesView.swift` 文件本身保留。** 上游仍在改动它,删掉会让
每次同步都产生冲突;它已无任何引用,不会编进界面。

**核心不动。** dyld hook、容器管理、多任务、插件注入都保持上游实现 ——
这部分对 iOS 版本极其敏感,应当跟随上游而不是自行分叉。

## 许可证

上游为 AGPL-3.0,本分支同样是 AGPL-3.0,完整源码即本仓库。
上游 README 保留为 [README-upstream.md](README-upstream.md)。

## 同步上游

```bash
git fetch upstream
git merge upstream/main
```

改动集中在 `LiveContainerSwiftUI/Views/LCTabView.swift`、
`Resources/Info.plist`、`Resources/Assets.xcassets/AppIcon.appiconset/`
和 `Resources/Localizable.xcstrings`,冲突面很小。

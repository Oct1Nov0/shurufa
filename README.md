# 中日键盘（自用）

自用的 iOS / iPadOS 键盘。拼音输入简体中文，拼音里可以直接夹打日语词。

本仓库基于开源输入法 [喵撲 Meowpuut](https://github.com/Krysta1ll/Meowpuut) 的代码和词库（MIT 授权，提交 `aaee845`）精简而来，原项目的版权声明见 [LICENSE](LICENSE)，词库来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 编译

推送到 `main` 分支后，GitHub Actions 会在 `xcode-27` 镜像上编译，产物是未签名的 `ZhJaKeyboard.ipa`，在 Actions 页面对应那次运行的 Artifacts 里下载。也可以在 Actions 页面手动点 Run workflow。

本地编译需要 macOS、Xcode、Rust、Python 3 和 XcodeGen：

```sh
bash scripts/prepare-ios.sh
xcodebuild -project iOS/ZhJaKeyboard.xcodeproj -scheme ZhJaKeyboard -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 安装

用 Sideloadly 把 ipa 签名安装到设备上，然后在「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」里加入「中日键盘」。

## 目录

| 路径 | 内容 |
| --- | --- |
| `crates/` | Rust 引擎和 C 接口 |
| `DataSources/`、`Resources/Lexicon/` | 词库来源数据 |
| `scripts/` | 词库编译和构建脚本 |
| `Sources/` | 引擎的 Swift 封装和候选栏的公共代码 |
| `iOS/Keyboard/` | 键盘扩展 |
| `iOS/App/` | 承载键盘的宿主 App，只有启用说明和试打框 |

# ReMirror

一个用回译法练习英语的 Windows / Android 应用。当前版本完成第一步：粘贴英文文章，选择翻译源，按段生成中文参考译文。

## 已实现

- Google Cloud Translation Basic (v2)、百度翻译开放平台通用翻译 API、OpenAI Chat Completions 兼容 API。
- 用户自行配置服务凭据；凭据通过设备安全存储保存。英文原文只发送给当前选择的翻译服务。
- 长文按段、按服务请求长度拆分，译文维持原段落顺序；显示进度、取消和错误信息。
- 自适应 Windows / Android 首屏、过渡动画、示例文章及译文复制。

目前还没有逆向写作和逐句对照界面。使用翻译服务前，需在对应平台开通 API 并填写自己的凭据。API 调用可能产生费用。

## 本地开发

安装 [Flutter 3.47.7](https://docs.flutter.dev/get-started/install)、Android SDK，以及用于 Windows 构建的 Visual Studio C++ 桌面开发组件和 ATL。检出后运行：

```powershell
flutter pub get
flutter test
flutter run -d windows
```

Android 运行时请将最后一行改为 `flutter run -d <设备 ID>`。`flutter devices` 可列出设备。

若重新生成 Android 工程，请运行 `dart tools/enable_android_internet.dart`，为正式版清单添加网络权限。

## 打包

`.github/workflows/build.yml` 在 GitHub Actions 上生成 Windows 安装程序和 Android APK，并将两者作为工作流构件上传。也可本地运行：

```powershell
flutter build windows --release
flutter build apk --release
```

Windows 安装程序通过 [Inno Setup](https://jrsoftware.org/isinfo.php) 编译 `installer.iss`。Android APK 使用 Flutter 模板的测试签名配置；正式发布需配置自己的 Android 发布签名。

## 服务配置

| 来源 | 需要填写 | 接口 |
| --- | --- | --- |
| Google | Cloud Translation Basic API Key | `translation.googleapis.com/language/translate/v2` |
| 百度 | APP ID、密钥 | `fanyi-api.baidu.com/api/trans/vip/translate` |
| AI | HTTPS 基础地址、API Key、模型名 | Chat Completions 兼容接口 |

AI 基础地址通常以 `/v1` 结尾；也可填写完整的 `/chat/completions` 地址。为保护密钥，当前版本只接受 HTTPS 地址。

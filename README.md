# ReMirror

一个用回译法练习英语的 Windows / Android 应用。粘贴英文文章并生成中文参考译文后，可逐句回译，最后对照英文原文检查文本差异。

## 已实现

- Google Cloud Translation Basic (v2)、百度翻译开放平台通用翻译 API、OpenAI Chat Completions 兼容 API。
- 内置英译简中离线来源：安装后可在首页选择“离线翻译”，无需 API 凭据；模型在设备上运行。
- 输入英文时可切换到“阅读查词”预览，点词查看中文释义、词性和音标；选中短语可查词，未收录短语以离线机器译文补充。提交回译后的原文同样可查词。参考译文可逐段修改后再开始回译。
- 用户自行配置服务凭据；凭据通过设备安全存储保存。生成译文时，英文原文发送给当前选择的翻译服务；启用 AI 点评时，点评内容另发送给配置的 AI 服务。
- 长文按段、按服务请求长度拆分，译文维持原段落顺序；显示进度、取消和错误信息。
- 自适应 Windows / Android 首屏、过渡动画、示例文章及译文复制。
- Windows 首页采用三栏练习面板；最近练习和逐句作答自动保存在本机，重启后可从记录继续。Android 界面保持原有布局。
- 译文按句呈现；点击句子填写英文回译，整篇结束后逐句显示原文、作答和文本差异。未作答句子也可提交。
- 配置 AI 接口后，所有翻译来源及导入练习在提交回译时自动获得逐句 AI 点评。点评按中文提示判断语义是否准确，允许与英文原文使用不同措辞；未作答句子跳过，失败可重试。
- 新生成的参考译文按英文原句逐句翻译并保存对应关系；一个英文句子即使译成多个中文短句，仍作为一条练习。生成后隐藏英文原文，直到回译结果页。旧版历史记录保留原有的按段落句序对应方式。
- 可在结果页将本轮练习导出为 XLSX；首页可导入上次的 XLSX，直接开始新一轮，无需重新调用翻译服务。提交本轮后可对照上轮答案，再次导出会保留旧工作表并追加新轮次。
- Windows 界面使用阿里巴巴普惠体 3.0；Android 界面英文使用 Liberation Serif，中文使用阿里巴巴普惠体 3.0。字体随应用打包。

文本差异只比较词语是否相同；配置 AI 后的点评会另行判断语义与表达。AI 点评会将中文提示、英文原文和你的回译发送给所配置的 AI 接口，结果仅在当前页面显示。Windows 会在本机保存练习记录；Android 若要跨次使用，请提交后导出 XLSX 并自行保存。使用翻译服务前，需在对应平台开通 API 并填写自己的凭据。翻译及 AI 点评调用可能产生费用。

## 练习文件

导入支持 `Greetings from Mars.xlsx` 示例布局及本应用导出的文件：工作表按“第一轮”“第二轮”等命名，A 列为中文参考，B 列为该轮回译，C 列为英文原文；首行为标题，空行分隔段落。“原文解析”等已有工作表会随下次导出一同保留。导入只读取最新一轮的句子与答案，新一轮作答时不显示旧答案，提交后才显示上轮答案。

## 本地开发

安装 [Flutter 3.47.7](https://docs.flutter.dev/get-started/install)、Android SDK，以及用于 Windows 构建的 Visual Studio C++ 桌面开发组件和 ATL。检出后运行：

```powershell
flutter pub get
flutter test
flutter run -d windows
```

Android 运行时请将最后一行改为 `flutter run -d <设备 ID>`。`flutter devices` 可列出设备。离线模型依赖 Android 9（API 28）或更新版本。

若重新生成 Android 工程，请运行 `dart tools/enable_android_internet.dart`，为正式版清单添加网络权限。

离线资源已随仓库保存；如需重建，安装 Python `zstandard` 后运行 `python tools/build_offline_assets.py`。资源来源、固定哈希和许可见 [assets/offline/SOURCES.md](assets/offline/SOURCES.md)。

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
| 离线翻译 | 无 | 设备内置模型，无网络请求 |

AI 基础地址通常以 `/v1` 结尾；也可填写完整的 `/chat/completions` 地址。为保护密钥，当前版本只接受 HTTPS 地址。

## 字体来源

- 阿里巴巴普惠体 3.0：版权归阿里巴巴（中国）有限公司，见 [官方字体网站](https://www.alibabafonts.com/) 与仓库中的 `assets/fonts/LICENSE-AlibabaPuHuiTi-3.0.md`。项目使用 Regular 和 Bold 字重，与阿里巴巴不存在合作或背书关系。
- Liberation Serif 2.1.5：来自 [Liberation Fonts](https://github.com/liberationfonts/liberation-fonts/releases)，使用 SIL Open Font License 1.1，见 `assets/fonts/liberation-fonts-ttf-2.1.5/LICENSE`。

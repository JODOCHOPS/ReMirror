# ReMirror

一个用回译法练习英语的 Windows / Android 应用。Windows 版采用“输入文章 → 阅读与分析 → 逐句回译”的流程；Android 版暂沿用原有翻译和练习界面。

## Windows 学习流程

1. 在输入框手动输入或粘贴文章，也可导入 TXT、MD、DOCX、PDF、XLSX。PDF 只读取可选中的文本，不支持扫描件 OCR。TXT/MD 使用 UTF-8 编码。
2. 点击“下一步：阅读与翻译”。应用按段落和英文句子组织内容；已有中英双语时保留中文，只用 AI 补译缺失的句子。英中句数不一致时会提示校对，英文和中文均可修改。
3. 阅读页每段上方显示英文、下方显示中文。点击英文句子可请求 AI 语法分析，点击单词可请求上下文词汇分析；生成的结果会保存在本机，再次点击可直接查看。单词分析弹窗可将单词加入生词库；顶部入口可跨文章查看和移除已收藏的单词。
4. 点击“下一步：回译训练”。每次根据一条中文提示写英文，提交后显示原句与 AI 对语法、语义、自然度的分别评价及改进建议。可修改后再次提交，所有作答均保留。也可跳过当前句并继续；最后一句有“结束”按钮，结束后显示已评价、已跳过和待练习句数。
5. Windows 自动保存文章、分析、收藏的生词和练习进度。首次使用新流程时会读取旧版 Windows 本地练习记录。可导出包含文章、语法分析、生词和每次回译评价的 XLSX，并再次导入继续使用。普通 XLSX 可手动选择工作表、英文列和中文列；旧版 ReMirror 练习 XLSX 也可导入。

Windows 的翻译、语法分析、词汇分析和回译评价使用用户配置的 HTTPS Chat Completions 兼容 AI 接口。请求失败时已完成的内容会保留，可重试失败项。AI 调用可能产生服务费用。

## Android 现有流程

- Google Cloud Translation Basic (v2)、百度翻译开放平台通用翻译 API、OpenAI Chat Completions 兼容 API。
- 内置英译简中离线来源：安装后可在首页选择“离线翻译”，无需 API 凭据；模型在设备上运行。
- 输入英文时可切换到“阅读查词”预览，点词查看中文释义、词性和音标；选中短语可查词，未收录短语以离线机器译文补充。提交回译后的原文同样可查词。参考译文可逐段修改后再开始回译。
- 用户自行配置服务凭据；凭据通过设备安全存储保存。生成译文时，英文原文发送给当前选择的翻译服务；启用 AI 点评时，点评内容另发送给配置的 AI 服务。
- 长文按段、按服务请求长度拆分，译文维持原段落顺序；显示进度、取消和错误信息。
- Android 首屏适配不同宽度，支持过渡动画、示例文章及译文复制。
- 译文按句呈现；点击句子填写英文回译，整篇结束后逐句显示原文、作答和文本差异。未作答句子也可提交。
- 配置 AI 接口后，所有翻译来源及导入练习在提交回译时自动获得逐句 AI 点评。点评按中文提示判断语义是否准确，允许与英文原文使用不同措辞；未作答句子跳过，失败可重试。
- 新生成的参考译文按英文原句逐句翻译并保存对应关系；一个英文句子即使译成多个中文短句，仍作为一条练习。生成后隐藏英文原文，直到回译结果页。旧版历史记录保留原有的按段落句序对应方式。
- 可在结果页将本轮练习导出为 XLSX；首页可导入上次的 XLSX，直接开始新一轮，无需重新调用翻译服务。提交本轮后可对照上轮答案，再次导出会保留旧工作表并追加新轮次。
- Android 可导入英文文章 TXT、Markdown、DOCX 和可选中文字的 PDF。导入后可检查、编辑原文，再手动生成中文参考译文；若当前已有文章或译文，会先确认是否替换。
- Windows 界面使用阿里巴巴普惠体 3.0；Android 界面英文使用 Liberation Serif，中文使用阿里巴巴普惠体 3.0。字体随应用打包。

文本差异只比较词语是否相同；配置 AI 后的点评会另行判断语义与表达。Android 若要跨次使用，请提交后导出 XLSX 并自行保存。使用翻译服务前，需在对应平台开通 API 并填写自己的凭据。翻译及 AI 点评调用可能产生费用。

## 练习文件

Android 旧练习文件支持 `Greetings from Mars.xlsx` 示例布局及旧版应用导出的文件：工作表按“第一轮”“第二轮”等命名，A 列为中文参考，B 列为该轮回译，C 列为英文原文；首行为标题，空行分隔段落。Windows 新版的 XLSX 导出另含 `_ReMirror` 数据工作表，用于完整恢复分析和多次作答。

## Android 英文文章文件

Android 的“导入文章”支持 `.txt`、`.md`、`.docx`、`.pdf`，最大 50 MB。TXT 和 Markdown 支持 UTF-8 及带 BOM 的 UTF-16 编码；Markdown 会清理格式标记和代码，保留正文、标题、列表及表格文字。DOCX 提取正文段落和表格文字。PDF 只提取可选中文字，扫描版不支持。导入结果可在输入框中编辑；复杂 PDF 的阅读顺序和段落可能需要手动调整。导入文章与“导入上次练习 XLSX”是两个独立入口。

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

Windows 新流程只使用 AI 配置；Android 现有流程仍可选择下列翻译来源。

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

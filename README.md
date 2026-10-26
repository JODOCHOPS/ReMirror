# ReMirror

一个用回译法练习英语的 Windows / Android 应用。两端均采用“输入文章 → 阅读与分析 → 逐句回译”的流程。Android 在手机宽度下将文章、导入和资料库操作收纳到顶部按钮及“更多功能”菜单。

## Windows / Android 学习流程

1. 在输入框手动输入或粘贴文章，也可导入 TXT、MD、DOCX、PDF、XLSX。PDF 只读取可选中的文本，不支持扫描件 OCR。TXT/MD 使用 UTF-8 编码。
2. 点击“下一步：阅读与翻译”。应用按段落和英文句子组织内容；已有中英双语时保留中文，只用 AI 补译缺失的句子。英中句数不一致时会提示校对，英文和中文均可修改。
3. 阅读页每段上方显示英文、下方显示中文。点击英文句子可请求 AI 语法分析，点击单词可请求上下文词汇分析。语法分析按“句子骨架、关键语法、中文理解”展示，可在 AI 设置中选择默认的入门、标准或进阶深度，也可在单句分析中切换；各深度分别缓存。旧版分析保留，可手动重新分析。单词分析弹窗可将单词加入生词库；同一词的不同例句合并为一个词条，在所有文章的阅读页及回译提交后显示的英文原句中高亮其规则和不规则词形。点击高亮词可先查看已有释义和例句，再按需分析当前用法。
4. 点击“下一步：回译训练”。每次根据一条中文提示写英文，提交后显示原句与 AI 对语法、语义、自然度的分别评价及改进建议。可修改后再次提交，所有作答均保留。也可跳过当前句并继续；最后一句有“结束”按钮，结束后显示已评价、已跳过和待练习句数。
5. 阅读页和回译提交后均可收藏句子；收藏库保留英中原句和已生成的语法分析，未分析的句子可以稍后补做。相同英中句子合并，校对句子后收藏内容同步更新。最近文章列表可删除整篇练习记录，删除前确认，删除后可短暂撤销；生词和收藏句子独立保留。
6. 两端自动保存文章、分析、收藏的生词、收藏的句子和练习进度。首次使用新流程时会读取设备上已有的旧版本地练习记录和生词。可导出包含文章、各深度语法分析、生词、句子收藏标记和每次回译评价的 XLSX，并再次导入恢复该文章的收藏信息。普通 XLSX 可手动选择工作表、英文列和中文列；旧版 ReMirror 练习 XLSX 也可导入，保留文件中的历史答案。

两端的翻译、语法分析、词汇分析和回译评价均使用用户配置的 HTTPS Chat Completions 兼容 AI 接口。请求失败时已完成的内容会保留，可重试失败项。AI 调用可能产生服务费用。

AI 凭据保存在设备安全存储中，文章和学习记录保存在各设备本地。设备间不自动同步；请用 XLSX 导出及导入转移文章和关联资料。两端均使用随应用打包的阿里巴巴普惠体 3.0，英文字体也包含 Liberation Serif。

## 练习文件

旧版 Android 练习文件支持 `Greetings from Mars.xlsx` 示例布局及旧版应用导出的文件：工作表按“第一轮”“第二轮”等命名，A 列为中文参考，B 列为该轮回译，C 列为英文原文；首行为标题，空行分隔段落。新版 XLSX 导出另含 `_ReMirror` 数据工作表，用于完整恢复分析和多次作答。

## 英文文章文件

“导入文件”支持 `.txt`、`.md`、`.docx`、`.pdf` 和 `.xlsx`。TXT/Markdown 请使用 UTF-8；DOCX 提取正文段落和表格文字，PDF 只提取可选中文字，扫描版不支持。导入结果可在输入框中编辑；复杂 PDF 的阅读顺序和段落可能需要手动调整。

## 本地开发

安装 [Flutter 3.47.7](https://docs.flutter.dev/get-started/install)、Android SDK，以及用于 Windows 构建的 Visual Studio C++ 桌面开发组件和 ATL。检出后运行：

```powershell
flutter pub get
flutter test
flutter run -d windows
```

Android 运行时请将最后一行改为 `flutter run -d <设备 ID>`。`flutter devices` 可列出设备。Android 工程当前最低支持 Android 9（API 28）。

若重新生成 Android 工程，请运行 `dart tools/enable_android_internet.dart`，为正式版清单添加网络权限。

离线资源已随仓库保存；如需重建，安装 Python `zstandard` 后运行 `python tools/build_offline_assets.py`。资源来源、固定哈希和许可见 [assets/offline/SOURCES.md](assets/offline/SOURCES.md)。

## 打包

`.github/workflows/build.yml` 在 GitHub Actions 上生成 Windows 安装程序和 Android APK，并将两者作为工作流构件上传。推送与 `pubspec.yaml`、`installer.iss` 版本一致的 `v*` 标签后，Windows 构建及检查通过时，会将 `ReMirror-Setup.exe` 发布到 [Releases](https://github.com/JODOCHOPS/ReMirror/releases)。Android APK 仍只作为工作流构件提供。也可本地运行：

```powershell
flutter build windows --release
flutter build apk --release
```

Windows 安装程序通过 [Inno Setup](https://jrsoftware.org/isinfo.php) 编译 `installer.iss`。Android APK 使用 Flutter 模板的测试签名配置；正式发布需配置自己的 Android 发布签名。

## 服务配置

两端均在“AI 设置”中填写 HTTPS 基础地址、API Key 和模型名，使用 Chat Completions 兼容接口。新学习流程不再提供 Google、百度和设备离线翻译入口。

AI 基础地址通常以 `/v1` 结尾；也可填写完整的 `/chat/completions` 地址。为保护密钥，当前版本只接受 HTTPS 地址。

## 字体来源

- 阿里巴巴普惠体 3.0：版权归阿里巴巴（中国）有限公司，见 [官方字体网站](https://www.alibabafonts.com/) 与仓库中的 `assets/fonts/LICENSE-AlibabaPuHuiTi-3.0.md`。项目使用 Regular 和 Bold 字重，与阿里巴巴不存在合作或背书关系。
- Liberation Serif 2.1.5：来自 [Liberation Fonts](https://github.com/liberationfonts/liberation-fonts/releases)，使用 SIL Open Font License 1.1，见 `assets/fonts/liberation-fonts-ttf-2.1.5/LICENSE`。

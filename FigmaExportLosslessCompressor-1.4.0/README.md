<!-- Created by Ray -->
<!-- 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray -->
<!-- 主要解决问题：说明终端交互安装、自动安装 oxipng、用户自定义导出目录和 ZIP 发布流程。 -->

# Figma 导出视觉无损压缩器

## 安装流程

双击：

```text
安装.command
```

安装器会：

1. 提示输入 Figma 导出文件夹的绝对路径。
2. 创建目录并校验可写权限。
3. 检查 `oxipng`。
4. 缺少 `oxipng` 时通过 Homebrew 自动安装。
5. 缺少 Homebrew 时先询问，用户确认后安装 Homebrew。
6. 注册 LaunchAgent。
7. 监听用户输入的目录，并在原路径替换压缩后的 PNG。

安装完成后，在 Figma Export 面板选择安装时输入的目录即可。

## 用户配置

用户输入的目录和实际 `oxipng` 路径保存在：

```text
config.local.env
```

后续升级程序不会覆盖该文件，也不会清空用户导出目录、缓存和日志。

如果终端环境变量 `FIGMA_EXPORT_DIR` 已设置，安装器会直接使用该路径，适合自动化部署。

## 目录限制

macOS TCC 会阻止 LaunchAgent 稳定访问以下目录：

```text
~/Desktop
~/Documents
~/Downloads
```

安装器会拒绝这些目录。推荐使用：

```text
~/FigmaExports
~/script/FigmaExports
~/Library/Application Support/FigmaExportInbox
```

## 工作方式

```text
Figma 导出 PNG 到用户目录
-> 检测文件写入稳定
-> SHA-256 内容去重
-> oxipng 视觉无损压缩
-> 原子替换原文件
```

同一内容只调用一次压缩算法。内容改名后复用缓存，不会重复压缩；压缩结果改名后通过结果哈希直接跳过。

## 压缩器模块

当前压缩器：

```text
compressors/oxipng.sh
```

模块接口：

```bash
compressor_validate
compress_image <输入文件> <临时输出文件> <日志文件>
```

替换算法时：

1. 新增 `compressors/<名称>.sh`。
2. 实现上述函数。
3. 修改 `config.env` 中的 `COMPRESSOR_NAME`。
4. 修改 `COMPRESSOR_ID`。
5. 重新运行 `install.sh`。

当前 `oxipng` 使用最高优化级别，并允许调整完全透明像素的不可见 RGB 值。可见像素保持不变，属于视觉无损。

## 命令入口

```text
安装.command
状态.command
卸载.command
```

也可以直接执行：

```bash
./install.sh
./status.sh
./uninstall.sh
```

`uninstall.sh --purge` 只在导出目录位于工具目录内时删除该目录；用户自定义目录不会被删除。

## 发布 ZIP

维护者执行：

```bash
./pack-release.sh
```

发布包生成于：

```text
releases/FigmaExportLosslessCompressor-1.4.0.zip
```

ZIP 只包含程序文件和双击入口，不包含：

```text
config.local.env
.state/
logs/
用户 PNG
.DS_Store
```

首次从浏览器下载后，如果 macOS 拦截未签名脚本，需要在 Finder 中右键 `安装.command` 并选择“打开”。

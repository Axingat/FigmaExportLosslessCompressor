<!-- Created by Ray -->
<!-- 版本：1.5.0  /  build：6  /  2026-09-24  /  Ray -->

# Figma 导出视觉无损压缩器

## 功能

自动监听用户指定的目标文件夹，对第一层 PNG 执行视觉无损压缩，并把结果放入 `compressed` 子目录。

```text
目标文件夹/
├── A.png
├── B.png
└── compressed/
    ├── A.png
    └── B.png
```

压缩输出通过 SHA-256 校验后，原 PNG 才会被删除。压缩失败、写入失败或校验失败时，原图会保留。

## 安装

1. 解压发布 ZIP。
2. 右键 `安装.command`，选择“打开”。
3. Terminal 提示时输入目标文件夹的绝对路径。
4. 安装器自动创建 `compressed` 子目录。
5. 如果缺少 `oxipng`，安装器会通过 Homebrew 自动安装。
6. 如果缺少 Homebrew，Terminal 会先询问，确认后再安装。

安装完成后，在 Figma Export 面板选择同一个目标文件夹。

## 使用

```text
Figma 导出 PNG 到目标文件夹
-> 工具检测第一层 PNG
-> 压缩到 compressed/同名文件
-> 校验输出哈希
-> 删除目标文件夹第一层的原 PNG
```

同一内容只压缩一次。文件改名后会复用缓存，不会重复调用 `oxipng`。

## 注意事项

- 仅支持 macOS。
- 只处理目标文件夹第一层的 `.png` 和 `.PNG`。
- 不扫描任何子文件夹，包括 `compressed`。
- 非 PNG 文件和子文件夹不会删除。
- 原图会在压缩结果验证成功后删除，请先备份重要文件。
- 不要选择 `~/Desktop`、`~/Documents`、`~/Downloads`，macOS 隐私保护可能阻止后台任务访问。
- 推荐使用 `~/FigmaExports` 或 `~/script/FigmaExports`。
- 首次安装如果缺少 Homebrew 或 `oxipng`，需要联网。
- 压缩属于视觉无损，可见像素不变；完全透明像素的不可见 RGB 值和无关元数据可能被优化。
- 浏览器下载的未签名 `.command` 可能被 Gatekeeper 拦截，需要右键选择“打开”。
- `compressed` 中已有同名文件时，会被新的压缩结果替换。

## 状态与卸载

双击 `状态.command` 可以查看监听状态、缓存数量和文件数量。

双击 `卸载.command` 会停止监听，但默认保留图片、缓存和日志。

需要彻底清理工具状态时执行：

```bash
./uninstall.sh --purge
```

自定义目标目录中的图片不会被 `--purge` 自动删除。

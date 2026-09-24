<!-- Created by Ray -->
<!-- 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray -->
<!-- 主要解决问题：定义压缩算法模块接口，使新增或替换算法不需要修改监听和去重主流程。 -->

# 压缩器模块接口

每个压缩器都是 `compressors` 目录下的独立 Shell 模块。

## 必需函数

```bash
compressor_validate
compress_image <输入文件> <输出文件> <日志文件>
```

- `compressor_validate` 返回 `0` 表示依赖可用，返回非 `0` 表示不可用。
- `compress_image` 必须生成输出文件，成功返回 `0`，失败返回非 `0`。
- 输出文件可以是压缩结果，也可以是没有收益时的原文件副本。
- 模块不能修改输入文件。

## 可选函数

```bash
compressor_description
```

用于返回当前算法的可读说明。

## 替换步骤

1. 在 `compressors` 中新增一个模块，例如 `my_compressor.sh`。
2. 实现上述函数，并添加 `Created by Ray`、版本、build、日期和账号注释。
3. 修改 `config.env` 中的 `COMPRESSOR_NAME`。
4. 同时修改 `COMPRESSOR_ID`，避免沿用旧算法的压缩缓存。
5. 重新运行 `install.sh`。

主流程只负责监听、哈希去重、缓存和输出发布，不依赖具体压缩工具。

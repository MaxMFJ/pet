# Spine JSON Web

本地 Web 原型，用来给第三方 Spine skeleton 转换器提供一个可视化壳。

当前原型特性：

- 上传 `.skel` 或 `.json`
- 调用本机第三方可执行文件
- 回传转换结果并支持下载
- 保存本地转换器路径和参数模板
- 不依赖任何外部 npm 包

## 运行

```bash
cd /Users/lzz/Desktop/桌面天堂/spine-json-web
npm start
```

默认地址：

```text
http://127.0.0.1:4318
```

## 配置转换器

界面里需要填写三项：

1. `可执行文件路径`
2. `参数模板`
3. `工作目录`（可选）
4. `锁定输出版本`（可选）
5. `输出版本`（例如 `3.8.75`）

支持的占位符：

- `{input}`
- `{output}`
- `{mode}`
- `{filename}`

如果希望固定输出给 DesktopPet 使用，推荐开启 `锁定输出版本`，并填写：

```text
3.8.75
```

例如，如果你的第三方工具调用方式是：

```bash
/path/to/converter --input /tmp/a.skel --output /tmp/a.json
```

那参数模板就填：

```text
--input {input} --output {output}
```

## 候选第三方工具

### 1. wang606/SpineSkeletonDataConverter

- 仓库：<https://github.com/wang606/SpineSkeletonDataConverter>
- 定位：`skel/json` 双向转换，多版本转换
- 许可：`PolyForm Noncommercial 1.0.0`
- 备注：非商用原型很合适，商业用途要单独评估许可

### 2. kiraio-moe/Skel2Json

- 仓库：<https://github.com/kiraio-moe/Skel2Json>
- 定位：更简单的 `skel/json` 转换
- 许可：`GPL-3.0`
- 备注：仓库已归档，支持范围较窄，README 推荐改用 `SpineSkeletonDataConverter`

## 现阶段边界

这个原型已经把本地 web 壳和可执行文件适配层做好了，但还没有把某个第三方仓库直接编译进来。
如果下一步能把目标仓库源码或已编译二进制放到本机，我可以继续帮你把它接成默认适配器。

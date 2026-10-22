# Novelverse local API

独立的 Python 本地开发服务，Python 3.10+ 即可运行，无第三方依赖。书籍 JSON 和 203 章原始正文在 `data/books/`，不再随 Flutter App 打包。

在仓库根目录启动：

```sh
make server
# 或 python3 server/app.py
```

默认监听 `127.0.0.1:8787`，书籍接口延迟 150 ms，可并发处理当前章和相邻章的请求。健康检查：

```sh
curl http://127.0.0.1:8787/health
```

| 方法 | 地址 | 内容 |
| --- | --- | --- |
| GET | `/health` | 服务状态 |
| GET | `/api/v1/books` | `{"items": [...]}` 书单 |
| GET | `/api/v1/books/{bookId}` | 详情，内嵌完整第一章 |
| GET | `/api/v1/books/{bookId}/recommendations` | `{"items": [...]}` 推荐 |
| GET | `/api/v1/books/{bookId}/chapters` | 目录元数据，不含正文 |
| GET | `/api/v1/books/{bookId}/chapters/{chapterId}` | 单章正文、版本、顺序 |

测试书 ID：`claimed-ruthless-alpha`。章节 ID 示例：`alpha-001`、`alpha-150`、`alpha-203`。可以直接获取第 150 章，无需下载前 149 章。推荐暂时指向同一本测试书。封面沿用 JSON 中的外部 HTTPS 地址。

不存在的书、章节和地址返回 HTTP 404；数据读取异常返回 500；响应错误格式为 `{"error":{"code":"...","message":"..."}}`。服务不提供文件目录浏览或写入接口。

## App 连接

先启动服务，再在另一个终端运行 App。

- **iOS 模拟器**：`make run-dev`，使用 `config/dev.json` 的 `http://127.0.0.1:8787/api/v1/`。
- **Android USB 真机**：`make run-dev-android`。该命令先执行 `adb reverse tcp:8787 tcp:8787`，再启动 App；多设备时加 `DEVICE=<设备ID>`。断开 USB 或重启设备后重新映射。IDE 启动时先运行 `make android-reverse`，再选择 `Novelverse dev (local API)`。
- **Android 模拟器**：`make run-dev-emulator`，使用 `config/dev_android_emulator.json` 的 `http://10.0.2.2:8787/api/v1/`。

Makefile 的 ADB 默认位置为 macOS Android SDK；其他安装位置用 `ADB=/path/to/adb` 覆盖。修改 `dart-define` 后需要重新运行 App，热更新不会改变编译配置。

Android 本地 HTTP 白名单只放在 Debug 资源中；iOS Debug 使用 `Info-Debug.plist` 允许本地连接，Release 继续使用原 `Info.plist`。新增公共 iOS 应用元数据时，同步维护两个 plist。

如果需要 Wi-Fi 真机调试，可以显式使用 `python3 server/app.py --host 0.0.0.0`，将 `API_BASE_URL` 改为电脑的局域网地址。Android Debug 的网络白名单需补入该具体地址；iOS 真机首次访问局域网时按系统提示允许本地网络访问。本次默认联调使用 USB 和回环地址。

## 数据与调试

```sh
python3 server/app.py --port 8787 --delay-ms 800  # 模拟较慢的响应
python3 server/app.py --data-dir /path/to/books # 使用其他书籍数据目录
make check-server                              # Python 真实 HTTP 测试
make check-api                                 # 运行 App 相同的 Dio API / 模型验证
```

现有 JSON 内容每次请求重新读取；新增书籍目录后重启服务。原始正文文件保留不动，响应仅统一换行、去掉与目录匹配的标题行。修改章节正文时同步更新目录里的章节 `version`；修改目录时同步更新 `catalogVersion` 与目录 `version`，让 App 的版本化缓存失效。

服务关闭后，App 会显示请求失败和 Retry，不会改回内置假数据。已有正文缓存、进度和收藏仍按原逻辑工作；详情信息当前需要服务在线。

平台配置参考：[Flutter HTTP 调试配置](https://docs.flutter.dev/release/breaking-changes/network-policy-ios-android)、[Apple 本地网络配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。

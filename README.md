# Novelverse

Flutter Android / iOS 基础工程。当前只包含基础设施和显示应用名称的占位页，没有产品业务逻辑。

## 环境与启动

已使用 Flutter **3.47.7 stable** / Dart **3.13.5** 进行开发。依赖版本记录在 `pubspec.yaml` 和 `pubspec.lock`，App 项目应提交锁文件。

```sh
make setup
make run-dev
```

不使用 Make 时执行：

```sh
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter run --dart-define-from-file=config/dev.json
```

VS Code 已提供 dev / staging / prod 启动配置。

## 技术选型

| 能力 | 方案 |
| --- | --- |
| 状态管理与依赖注入 | Riverpod，注解与代码生成 |
| 网络 | Dio，类型化异常、取消请求、上传下载、可选元数据日志 |
| 数据库 | Drift + SQLite，后台连接、环境隔离、schema 快照 |
| 简单配置 | SharedPreferencesAsync |
| 敏感信息 | flutter_secure_storage |
| 多语言 | Flutter gen-l10n + ARB + intl |
| 路由 | go_router |
| 日志 | logger，通过 AppLogger 统一使用 |
| JSON | json_serializable + build_runner |

## 目录与边界

```text
lib/
  main.dart                     # 统一入口
  app/
    bootstrap.dart              # 初始化、错误处理、依赖注入
    app.dart                    # MaterialApp、语言与主题
    router/                     # 路由
    settings/                   # 应用设置、持久化、状态管理
    theme/                      # Material 3 明暗主题
  core/
    config/                     # 环境配置
    database/                   # 数据库连接与生命周期
    errors/                     # 基础异常
    logging/                    # 日志
    network/                    # HTTP 传输、异常转换
    providers/                  # 基础服务依赖
    storage/                    # SP、安全存储
  l10n/                         # ARB 与生成的本地化代码
config/                         # 三环境的编译配置
drift_schemas/                 # 已提交的数据库历史 schema
test/                          # 基础设施和应用接线测试
```

后续业务放在 `lib/features/<feature>/`，按需要增加 `data/`、`application/`、`presentation/`；复杂业务再增加 `domain/`。页面通过 Provider / Repository 使用服务，网络基础层不依赖用户管理、路由或业务模型。

目前没有预建业务表、登录流程、接口加密协议或业务响应结构。外部 SDK 需要时再接入启动流程。

## 环境配置

| 参数 | 取值 / 含义 |
| --- | --- |
| `APP_ENV` | `dev`（默认）、`staging`、`prod` |
| `API_BASE_URL` | 可带路径的 HTTP(S) 基地址，默认留空 |
| `HTTP_LOG_ENABLED` | 是否记录 HTTP 元数据，默认 false；prod / Release 强制关闭 |

编辑 `config/*.json` 填入实际 API 地址。也可以临时覆盖单个参数：

```sh
flutter run --dart-define-from-file=config/dev.json --dart-define=API_BASE_URL=https://your-api.example/v1/
```

未配置后端时仍可启动 App；相对路径请求会立即抛出 `ConfigurationException`，不会向占位服务器发请求。配置错误或存储读取失败时显示可重试的通用启动错误页，详情写入日志。

三环境通过数据库文件名与存储 Key 前缀隔离数据。当前共用 Android applicationId / iOS bundle identifier；如需三套 App 同时安装，下一步再增加原生 flavors / schemes。

`dart-define` 值会随 App 打包，不能用来保存服务端私钥。配置目录中没有真实凭证。

## 状态与设置

基础服务由 `core/providers/core_providers.dart` 提供。配置、日志和启动时读取的设置通过根 `ProviderScope` 注入，测试可以覆盖对应 Provider。

- 长期服务使用 `@Riverpod(keepAlive: true)`。
- 页面状态默认使用 `@riverpod`，随监听者释放；取消请求可接入 `ref.onDispose(cancelToken.cancel)`。
- 根 Scope 关闭自动重试。后续仅对适合重试的读取操作显式配置策略。
- 异步操作结束后访问 Provider 时，检查 `ref.mounted`。
- Dio、GoRouter、数据库连接在所属 Provider 释放时关闭。

```dart
final settings = ref.read(settingsControllerProvider.notifier);
await settings.setLocale(const Locale('zh'));
await settings.setLocale(null); // 跟随系统，运行期间系统切换也会生效
await settings.setThemeMode(ThemeMode.dark);
await settings.setThemeMode(ThemeMode.system);
```

语言和主题在显示主界面前读取，默认均跟随系统。设置写入按顺序执行，持久化成功后更新状态；失败会返回异常，后续写入仍可继续。

## 网络与异常

使用 `apiClientProvider` 获取客户端。`get` / `post` 提供常用入口，`request` 支持其他方法、FormData、字节和流式响应，`download` 提供文件下载。

```dart
final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
  'your-endpoint',
  queryParameters: {'page': 1},
  cancelToken: cancelToken,
  decode: (data) => data as Map<String, dynamic>,
);
```

`decode` 只负责解释当前接口的返回数据，业务响应包裹、业务错误码、鉴权和 Token 刷新由后续 API / Repository 层按真实协议实现。

- `NetworkException` 区分超时、连接、取消、HTTP 和未知错误，保留 HTTP 状态码与原始异常。
- `DataFormatException` 表示响应 JSON / 模型解析失败。
- `ConfigurationException` 表示缺少请求配置。
- 页面根据异常类型选择本地化文案，不直接展示底层错误字符串。

默认连接超时 10 秒，发送和接收超时 30 秒。单次请求可通过 Dio `Options` 覆盖。没有全局自动重试，也没有全局弹 Toast 或导航行为。

## 存储与数据库

`preferencesStoreProvider` 提供类型明确的异步 SP 读写，仅保存少量非敏感设置；失败不会静默返回成功。`clear()` 只清除当前命名空间。

`secureStoreProvider` 提供 `read`、`write`、`delete`、`clear`，用于 Token 等敏感字符串。Android 已排除加密值与包裹密钥文件的云备份 / 设备迁移，iOS 已关联 Keychain entitlement。Keychain 数据可能跨卸载保留，首次安装和退出登录如何清理需由后续账户流程决定。

`appDatabaseProvider` 延迟创建数据库，文件放在应用支持目录，连接由 Drift 在后台管理。当前 schemaVersion 为 1，**没有业务表**，外键约束已开启。测试可用 `AppDatabase(NativeDatabase.memory())` 注入内存数据库。

增加或修改表时：

1. 修改表定义和数据库注册，并递增 `schemaVersion`。
2. 执行 `make migrations`，保留历史 schema 快照。
3. 实现生成步骤要求的升级逻辑，补充迁移和数据完整性测试。
4. 执行生成与检查。不能通过删除用户数据库替代正式迁移。

## 多语言与主题

当前 ARB 包含英文、简体中文（`zh`）、繁体中文（`zh-Hant`）。新增文案先修改 `app_en.arb`，再补其他语言；新增语言以生成的 `AppLocalizations.supportedLocales` 为准。

```sh
flutter gen-l10n
```

文案使用 `AppLocalizations.of(context)`；日期、数字、复数按 ARB / intl 规则处理。iOS 的 `CFBundleLocalizations` 同步维护支持语言。

主题集中在 `app/theme/app_theme.dart`，使用 Material 3 的 ColorScheme 和 ThemeData。布局优先使用 Flutter 自身约束、SafeArea 和 MediaQuery，后续根据设计稿决定是否需要额外屏幕适配库。

## 日志与错误处理

业务和基础设施统一通过 `appLoggerProvider` 使用 AppLogger。Debug 开发环境输出 debug 及以上级别；prod 或 Release 输出 warning / error。

可选 HTTP 日志只记录方法、地址路径、状态和耗时，不记录请求头、查询值、请求体、响应体。路径本身及手写日志也应避免包含凭证和用户内容。

启动流程已接入 Flutter 框架错误和 PlatformDispatcher 未处理错误。本地日志目前输出到控制台；需要文件轮转或线上崩溃上报时，再增加输出实现。

## 生成与验证

```sh
make generate                  # 本地化、Riverpod、Drift、JSON 生成
make check                     # 格式检查、静态分析、测试
```

生成文件与数据库 schema 快照应和源代码一起提交，不能手工修改生成文件。改完代码后，可执行 `dart format lib test`。

测试覆盖网络解析 / HTTP / 超时 / 取消、日志敏感值排除与级别过滤、资源释放、SP / 安全存储的环境隔离、数据库初始化 / 事务回滚、设置并发写入 / 失败恢复，以及路由 / 明暗主题 / 系统语言切换。

平台编译：

```sh
flutter build apk --debug --dart-define-from-file=config/dev.json
flutter build ios --simulator --debug --dart-define-from-file=config/dev.json
```

安全存储的 Dart 测试使用官方模拟实现；正式发布前仍需在已签名 iOS 真机和 Android 设备上验证原生读写。发布签名与分发配置尚未接入。

# Novelverse

Flutter Android / iOS 小说 App。目前包含基础架构、原型版书籍详情页，以及从 `readers` 迁入的完整阅读器。默认启动进入测试书籍详情页。

## 环境与启动

已使用 Flutter **3.47.7 stable** / Dart **3.13.5** 进行开发。依赖版本记录在 `pubspec.yaml` 和 `pubspec.lock`，App 项目应提交锁文件。

```sh
make setup
make server       # 单独终端启动 Python API，并自动恢复 Android USB 端口映射
make run-dev      # iOS 模拟器；Android USB 真机用 make run-dev-android
```

不使用 Make 时执行：

```sh
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter run --dart-define-from-file=config/dev.json
```

VS Code 已提供 dev / Android emulator / staging / prod 启动配置；Android Studio 可选择共享的 `Novelverse dev (local API)` 配置。首次接入本地服务的步骤见 [server/README.md](server/README.md)。

## 技术选型

| 能力 | 方案 |
| --- | --- |
| 状态管理与依赖注入 | Riverpod，注解与代码生成 |
| 网络 | Dio，类型化异常、取消请求、上传下载、可选元数据日志 |
| 数据库 | Drift + SQLite，后台连接、环境隔离、schema 快照 |
| 简单配置 | SharedPreferencesAsync |
| 敏感信息 | flutter_secure_storage |
| 英文文案 | Flutter gen-l10n + ARB + intl，仅英文 |
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
  features/
    books/                      # 详情、推荐、收藏、模拟 API 与正文缓存
    reader/                     # 双模式阅读、分页、设置、阅读进度
  l10n/                         # ARB 与生成的本地化代码
server/                         # 独立 Python HTTP 服务、书籍 JSON 和正文
tool/                           # HTTP 联调检查脚本
config/                         # 环境和模拟器地址配置
drift_schemas/                 # 首发结构快照，发布后保留后续历史版本
test/                          # 基础设施和应用接线测试
```

后续业务放在 `lib/features/<feature>/`，按需要增加 `data/`、`application/`、`presentation/`；复杂业务再增加 `domain/`。页面通过 Provider / Repository 使用服务，网络基础层不依赖用户管理、路由或业务模型。

当前业务表仅包含阅读进度和收藏。演示数据通过 Python HTTP 服务及 BookApi 接口提供；登录、支付和真实服务端协议尚未接入。

## 书籍详情与阅读器

### 真实测试书籍与接口

真实正文来自参考项目 `readers`：**Claimed By The Ruthless Alpha**，作者 **Ofotokun Bridget**。203 章正文总计约 1.17 MB，平均每章约 5,700 字符，最大一章约 11,400 字符。原始章节文件完整保留在 `server/data/books/`；服务端响应时仅移除与目录匹配的独立标题行，统一换行。JSON 和正文不再打包进 App。

阅读量、收藏量、评分和六本推荐为模拟数据。详情、书单及推荐 JSON 的 `coverUrl` 都使用提供的 HTTPS 封面地址，组件按真实网络方式加载，加载中、缺图及失败时显示简单占位图，不再打包或裁切原型封面素材。推荐 JSON 的 `targetBookId` 暂时指向这本真实测试书；未提供该字段时使用推荐书自身 ID，页面不指定测试书 ID。

`HttpBookApi` 通过已有 Dio / ApiClient 请求 Python 本地服务，默认每次书籍请求延迟 150 ms。书名、简介、统计、推荐、封面地址与推荐跳转目标均来自 HTTP 响应；封面通过独立 HTTPS 请求加载。服务关闭时显示网络错误，不回退到 App 内置数据。`MockBookApi` 仅保留在测试目录，读取服务端 fixture 以隔离单元测试。后续服务端沿用当前协议时，修改 `API_BASE_URL` 即可；协议有变化时只调整数据层。

| 接口 | 返回 |
| --- | --- |
| `GET /api/v1/books/{id}` | 基本信息、简介、标签、统计、目录版本、**完整第一章** |
| `GET /api/v1/books/{id}/recommendations` | 独立推荐列表，可独立失败和重试 |
| `GET /api/v1/books/{id}/chapters` | 目录 ID、顺序、标题、正文版本，**不含各章正文** |
| `GET /api/v1/books/{id}/chapters/{chapterId}` | 单章正文 |

详情附带的第一章直接进入同一正文缓存，阅读器不再重复请求。详情布局对照提供的 HTML 原型：紧凑封面与信息、不显示作者、单行小标签、阅读统计、最多四行简介（Read more / Show less）、半章预览、渐隐 Continue Reading、三列两行推荐和固定底部操作栏。浅紫背景随书籍头部滚动，正文区使用统一暖白纸色。顶栏底色和书名随滚动距离渐显，状态栏透明并使用深色图标，避免 Android 顶部灰色遮罩和硬切换。页面按字素取约一半并尽量停在段落或单词末尾。

Start Free Reading 和 Continue Reading 都恢复上次阅读位置；没有记录时从第一章开始。Library 按钮持久化切换收藏，分享按钮打开系统分享面板。

### 跳章与进度

- 路由 `/books/claimed-ruthless-alpha/read` 恢复进度。
- 路由 `/books/claimed-ruthless-alpha/read?chapter=alpha-150` 直接从第 150 章开始，显式章节优先于已存进度。
- 阅读器默认在顶部显示当前章节，点屏幕中央显示返回、书名、章节和书签；底部提供 Contents / Theme / Settings，右下角爱心与详情页共用收藏状态。目录惰性加载并定位当前章，已加书签的章节显示书签标记。
- 左右分页、上下滚动、字号、行距和独立亮度设置均保留。Background 提供 Paper / Cream / Green / Blue / Night；Theme 在 Paper 与 Night 间切换，正文、工具栏、弹层和系统栏跟随配色，设置存 SP。产品主色为 `#8051C9`。
- 亮度通过 Android / iOS 原生通道控制，仅在当前阅读页临时生效，不写入 SP；退出阅读后还原，重新进入读取当前系统亮度。关闭设置面板不影响当前阅读亮度。字号、行距、翻页模式和背景保存到 SP，重启 App 后恢复。

进度以书籍 ID 为主键存入 Drift：稳定章节 ID、章节顺序、正文版本、**章内 UTF-16 字符偏移**和更新时间。分页页码不作为持久化坐标，避免改字号或屏幕尺寸后失效。目录插入章节后按 ID 找回目标；正文版本改变时重置到该章开头。

阅读期间最多每 500 ms 合并写入一次；退出、切后台立即 flush；写入串行，旧请求不会覆盖新进度。尚未加载或加载失败的目标章节不会覆盖最后有效记录。阅读位置 Provider 离页自动释放，重进和重启从数据库恢复。章节书签以 `(bookId, chapterId)` 为联合主键，附带章节标题、序号及保存时间；使用服务端稳定章节 ID，目录重新排序不会错绑。书签和收藏独立保存在 SQLite，切换、退出或重启后保留。

### 分层缓存

| 层 | 默认限制 | 保存内容 |
| --- | --- | --- |
| 阅读界面 | 平时当前章及前后各一章；连续滚动期间临时最多 10 章，停止后收回至当前窗口 | 正文、段落及已构建的文字组件 |
| 正文内存 LRU | 最多 10 章，约 1 MiB 文本预算 | 已请求的章节 |
| 分页结果 | 最近 10 章，同一布局条件 | 分页边界；字号或尺寸变化时重排 |
| 目录内存 | 最近 3 份目录 | 章节元数据 |
| 文件缓存 | 每环境最多 50 MiB / 5,000 项，30 天未访问过期 | 版本化目录和正文 JSON |
| Drift | 不随正文缓存淘汰 | 阅读进度、收藏 |

进入目标章节先请求并显示它，之后才预取下一章和上一章。2000 章目录也只加载目标及相邻正文，目录列表按可见项构建。相同章节并发请求合并，预取失败不会阻塞当前章，返回已读章优先复用缓存。

滚动正文使用原生 `CustomScrollView` 和双向 `SliverList` 按段落惰性构建。文字项使用稳定标识并复用组件，滑动中保留有限的已读内容、追加预取章节，正常跨章不重设文字锚点；停止滚动后再清理旧内容。达到临时上限或必须换锚点时在布局前校准位置，保留同一个滚动对象及手势。目录跳章、字号调整等主动操作才重新定位。阅读主题仅在配色或外层主题变化时重新生成。

磁盘缓存位于应用缓存目录 `reader_books_v2_<env>`，Key 包含书籍、章节及版本并以 SHA-256 生成文件名。原子写入、LRU 淘汰、过期清理及条目上限共同限制空间。系统删除缓存后重新获取正文，进度与收藏仍保留在应用支持目录的数据库中。文件缓存写入失败不影响已经取得的正文。

依当前真实数据量，2000 个同等大小章节约十余 MB，无需一次加载或排版整本书；50 MiB 是可调整的初始缓存预算，不是主动下载整本书。

## 环境配置

| 参数 | 取值 / 含义 |
| --- | --- |
| `APP_ENV` | `dev`（默认）、`staging`、`prod` |
| `API_BASE_URL` | 可带路径的 HTTP(S) 基地址，dev 指向本地服务；staging / prod 待配置 |
| `HTTP_LOG_ENABLED` | 是否记录 HTTP 元数据，dev Debug 默认 true，其余默认 false；prod / Release 强制关闭 |

dev Debug 未传 `API_BASE_URL` 时默认使用 `http://127.0.0.1:8787/api/v1/`，直接运行 `main.dart` 也能连接本地服务；显式配置的地址优先，Profile / Release、staging / prod 不使用该默认地址。

开发服务通过 `make server` 启动。`config/dev.json` 使用回环地址；Android USB 真机通过 `make android-reverse` 映射端口，Android 模拟器使用 `config/dev_android_emulator.json`。完整联调说明见 [server/README.md](server/README.md)。编辑 `config/*.json` 可切换实际 API 地址，也可以临时覆盖单个参数：

```sh
flutter run --dart-define-from-file=config/dev.json --dart-define=API_BASE_URL=https://your-api.example/v1/
```

未配置后端地址的环境仍可启动 App，但书籍请求会抛出 `ConfigurationException` 并显示加载失败。配置错误或存储读取失败时显示可重试的通用启动错误页，详情写入日志。

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
await settings.setThemeMode(ThemeMode.dark);
await settings.setThemeMode(ThemeMode.system);
```

应用固定为英文，不提供语言切换；旧版本存储的语言字段会忽略，保留主题设置。主题在显示主界面前读取，默认跟随系统。设置写入按顺序执行，持久化成功后更新状态；失败会返回异常，后续写入仍可继续。

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

`appDatabaseProvider` 延迟创建数据库，文件放在应用支持目录，连接由 Drift 在后台管理。当前为未发布的首发 schemaVersion 1，直接创建 `reading_progress_entries`（阅读进度）、`library_entries`（收藏）和 `chapter_bookmark_entries`（章节书签），外键约束已开启。本次重置了开发阶段的历史结构，旧开发包需卸载重装。测试可用 `AppDatabase(NativeDatabase.memory())` 注入内存数据库。

正式发布后，如需调整表结构：

1. 修改表定义和数据库注册，并递增 `schemaVersion`。
2. 执行 `make migrations`，保留历史 schema 快照。
3. 实现生成步骤要求的升级逻辑，补充迁移和数据完整性测试。
4. 执行生成与检查。不能通过删除用户数据库替代正式迁移。

## 英文文案与主题

当前产品仅支持英文，文案统一维护在 `app_en.arb`。主应用和启动失败页显式指定英文，系统语言变化不会改变界面语言。保留 ARB 生成流程以集中维护文案；iOS `CFBundleLocalizations` 也仅声明英文。

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

测试覆盖网络解析 / HTTP / 超时 / 取消、日志敏感值排除与级别过滤、资源释放、SP / 安全存储的环境隔离、数据库初始化 / 事务回滚、设置并发写入 / 失败恢复，以及路由 / 明暗主题 / 非英文系统下保持英文。

平台编译：

```sh
flutter build apk --debug --dart-define-from-file=config/dev.json
flutter build ios --simulator --debug --dart-define-from-file=config/dev.json
```

安全存储的 Dart 测试使用官方模拟实现；正式发布前仍需在已签名 iOS 真机和 Android 设备上验证原生读写。发布签名与分发配置尚未接入。

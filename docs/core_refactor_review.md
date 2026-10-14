# 核心重构集中审核

日期：2026-10-11。审核范围是当前未提交的同步 runtime 重构、直接调用/批量调用优化、
eval 执行器，以及相应测试、性能入口和报告。没有提交或暂存代码。

## 发现与修复

| 优先级 | 问题与触发条件 | 最终修复 |
| --- | --- | --- |
| P1 | call/run 等待 Promise 超时后仍占用原生 async_promise 槽，后续调用报 already running。local/worker、root/child 都已复现。 | 超时与取消退出时释放存活 Context 的等待槽；已销毁的 Context 不再访问原生指针。 |
| P1 | worker Context 销毁后，正在等待的注入回调返回 Stream，仍会创建失去归属的订阅。修改前订阅数为 1。 | 编码、注册 Stream 和回传之前检查 runtime 与原回调所属 Context 仍存活；迟到结果丢弃，修复后订阅数为 0。 |
| P1 | 同步宿主回调里调用 engine.dispose，队列在回调返回后覆盖 closed 状态。修改前最终状态错误地变成 ready。 | 在进入 FFI 前登记 running Future 和状态，生命周期操作可以等待已登记的任务。 |
| P1 | stop 与 dispose 同时发生时可能发送两个销毁命令。完整 UI 生命周期回归捕获 runtime is closed 的未处理错误。 | stop 只设置中断标记并复用 dispose Future；engine.dispose 同时等待停止与运行收尾，移除未等待的 stop 路径。 |
| P2 | 异步返回的 C 字符串尚未被读取时，取消检查提前抛出，遗漏释放。 | 明确字符串所有权转移；所有提前退出都由 finally 释放尚未消费的字符串。 |
| P2 | 多个异步 Context 在 worker 关闭后各自收尾，可能重复释放 NativeCallable。 | worker 等待 whenIdle，回调释放幂等；清空关闭 runtime 的回调与归属注册表。 |
| P2 | restart 期间同步入口可能访问旧 runtime；raw 同步入口将零毫秒误当作无限时限。 | 重启期间同步入口明确拒绝；raw 与结构化同步入口统一拒绝已耗尽的时限，不执行源码。 |
| P2 | eval 执行器给 JS Error 写入 fileName，对 frozen Error 无效，也会改变调用方错误对象。 | 在 Dart 异常元数据边界补充求值源码名称，保留原始 JS 对象；同步、异步和 frozen Error 均测试。 |
| P3 | invocation 的 JS_NewString 异常检查重复；isolated adapter 只检查接口类型，忽略 supportsSync 值；API 注释仍称所有回调都返回 Promise。 | 删除重复分支，读取实际能力值，修正同步返回值与 Future/Promise 的说明。 |

清理集中在拥有状态与资源的 engine/executor/transport 边界，没有添加页面专用补丁，
没有恢复旧 worker-only 分支。并发销毁及停止均有独立回归测试。

## 验证

- Windows 原生 Release DLL 构建通过，最终 Release benchmark 构建通过。
- 核心 271 项、UI 283 项全部通过。
- 核心、UI、测试及三个性能入口静态分析无问题；git diff --check 通过。
- 新增 core_review_test.dart，覆盖本地与 worker、root/child 超时恢复、迟到 Stream、
  回调内销毁、重启与零时限、两个并发 Context 销毁，以及 stop/dispose 共用收尾。
- 已复核直接调用的 receiver、全局函数替换、句柄归属、批量顺序/异常停止、
  参数与结果转换限制、eval 作用域和临时 globals 恢复；相关既有测试继续通过。

Release CPU 复测采用原有 invocation_benchmark 入口，15 个样本，测试和编译完成后
单独运行；没有同时运行其他性能进程。单位 μs/次，样本中位数：

| 路径 | 审核后 |
| --- | ---: |
| JS 行函数单次同步 | 24.16 |
| JS 行函数单次 Future API | 30.62 |
| 同步每批 20 的单行成本 | 20.16 |
| Future 每批 20 的单行成本 | 21.41 |
| 无参数 raw eval | 4.011 |
| 结构化 evalSync | 16.810 |
| evalSync 带临时 globals | 23.623 |

此前 eval 优化前的对应值为 4.093、34.843、126.951 μs；包装层优化收益仍保留。
前后数据不是帧率结论，也不证明所有工作负载都没有性能波动。
本次 hostRow 的 Future 批次 100 比批次 20 更慢，再次说明不能据简单基准设置统一批量大小。
完整分布见 [审核后原始数据](core_refactor_review_results.json)。

## 验证边界

本次运行验证在 Windows 原生后端完成，没有实际运行浏览器、Android、iOS、macOS 或 Linux。
Web 相关源码已静态分析，仍不支持同步入口。原列表帧率及 RSS 报告没有在本次审核修复后重采样；
资源释放结论来自所有权审核和生命周期回归，不是对整个进程堆的泄漏检测。

超时释放的是本次桥接等待槽，不会取消任意外部 Future 或撤销已发生的副作用。
需要停止网络请求或宿主工作时仍须合作式取消，释放 Context/runtime 可阻止迟到结果回传。
长同步代码依然占用所属 isolate；无超时的同步死循环不会让 Dart Timer 获得执行机会。

在本轮审核范围内，已确认的问题均已修复；上述平台与内存验证边界保持明确。

## 第二轮审核

再次审核集中在启动、重启、关闭及绑定替换的生命周期。新增 18 项回归测试，分别覆盖 currentIsolate 与 workerIsolate。

| 优先级 | 已复现问题 | 修复 |
| --- | --- | --- |
| P1 | 子 Context 加载启动资源期间关闭 runtime，访问尚未初始化的 engine，触发 LateInitializationError。 | 按初始化阶段释放 engine 或已建立的 adapter；原生资源可及时关闭，外部资源 Future 不由此取消。 |
| P1 | 重启后旧函数句柄的 id 被新 runtime 重用，旧句柄可调用或删除新函数。旧对象、类句柄释放也可能误删新绑定。 | 统一句柄生命周期，记录所属 runtime 身份；跨 runtime 的句柄不可调用，也不释放新 runtime 的绑定。 |
| P1 | 已关闭 worker 的 createContext 等请求仍入队，Future 永久等待。 | 关闭后的请求立即返回 JsRuntimeClosedException，仅内部关闭命令允许继续。 |
| P1 | 替换全局宿主函数后，已经开始的旧异步调用因回调被解绑而丢弃结果，Promise 永不结束。 | 捕获调用原属 Context，按其生命周期决定回传；替换函数允许旧调用完成，销毁 Context 仍丢弃迟到结果。Stream 也使用捕获的 Context 登记归属。 |
| P2 | 同一 runtime 内重绑同名对象或类，旧句柄释放误删新绑定，保存的旧对象引用未标记失效。 | Context 内按绑定身份登记状态；释放原状态，仅在全局绑定仍匹配时删除全局属性。 |
| P2 | run 包装的局部 value、convert 遮蔽用户同名全局变量。 | run 复用已有核心求值及结果转换通道，用户源码通过间接 eval 在正常全局作用域建立 async 函数。 |

初始 10 项生命周期测试修复前有 9 项失败；函数替换的两个后端均复现等待超时。修复后新增测试与第一轮的迟到 Stream、超时恢复、并发关闭测试共同通过。

最终验证：核心 **289 项**、UI **283 项**全部通过；核心、UI、测试及三个 benchmark 入口静态分析无问题，git diff --check 通过。日志位于 build/core-review-round2-core-tests.log、build/core-review-round2-ui-tests.log、build/core-review-round2-analyze.log。

本轮没有重新采样 Release 性能、列表帧率或内存；前文性能数据属于第一轮版本，不作为第二轮性能验收结果。运行验证仍限 Windows 原生后端。本轮改动未提交。

## 第三轮审核与最终版本复测

本轮重新复核句柄所属 runtime、Context 初始化与关闭、回调替换和迟到结果、原生返回值所有权、同步重入及中断边界，以及统一调用/求值通道。未发现新的已确认源码缺陷，未修改核心生产行为。

### 构建及回归

- 独立 Release DLL：核心 289 项通过；UI 283 项通过。
- demo 实际打包的 Release DLL：清理原生构建缓存并重编后，核心 289 项、UI 283 项均通过。
- demo 实际打包的 Debug DLL：核心 289 项通过。
- 核心、UI、全部测试及 demo 全部 lib 静态分析通过；git diff --check 通过。
- demo 的 Windows Debug 主入口 lib/main.dart、Windows Release 性能入口、Web Release 主入口均构建成功。
- IDE XML 检查确认 main.dart 在注册模块的内容根内且不在排除目录；没有自动操作 IDEA 验证设备选择器或调试启动。

重要构建发现：最初 demo 包内的旧 Release DLL 在核心测试中途退出，剩余测试记录为 did not complete。独立 DLL 的同组测试正常；清理 demo 原生构建缓存并重编后，实际打包 DLL 的完整测试通过。不能将第一次的中断报告为最终测试失败，也不能仅凭增量构建成功推断打包产物已经更新。此前该旧产物的性能数据不用于本轮验收。复测 DLL SHA256 记录于原始 JSON。

### Release 复测

使用既有分层 benchmark，原生 Flutter 为基线，保留相同视口、行高、滚动驱动与两轮反序采样。各组每轮超过 400 帧。没有在性能采样同时运行测试、编译或另一个性能进程。最终数据见 [第三轮原始结果](core_refactor_review_round3_results.json)。

| 模式 | 帧样本总数 | UI 平均 ms | 每轮 UI P90 ms | UI 超预算帧 |
| --- | ---: | ---: | ---: | ---: |
| 原生 Flutter | 904 | 0.247 | 0.308～0.408 | 0 |
| 同步 JS builder | 921 | 0.286 | 0.489～0.517 | 0 |
| 本地批量虚拟列表 | 886 | 0.248 | 0.335～0.357 | 0 |
| worker 批量虚拟列表 | 913 | 0.269 | 0.364～0.377 | 0 |

原生行生成约 0.0029 ms/行，同步 JS 行生成约 0.148 ms/行。JS 行生成成本仍高于原生；该简单文本场景下整体 UI 帧耗时接近，不能推断复杂业务行性能相同。所有组 Raster 和 Total 超预算帧也为 0。

同一最终列表入口附带的调用基准：同步 JS 单行 23.140 μs，每批 20 的单行成本 20.110 μs，每批 100 为 19.269 μs。独立 eval 复测：raw 约 4.17 μs，结构化约 18.06 μs，临时 globals 约 24.88 μs。数值存在运行间波动，未回到优化前结构化 34.843 μs、临时 globals 126.951 μs 的水平；没有据此调整生产配置。

### item 生命周期与进程内存

三个模式各用独立 Release 进程，向前 480 行、回到起点、向前 960 行，随后移除页面。相同探针记录 Widget 与 State。

- 原生与同步 JS builder：Widget 创建 1932 次，State 挂载/最终销毁均为 1932，峰值活跃 State 25，移除后活跃 State 0，没有历史 Widget 缓存。
- 本地批量虚拟列表：创建并保留 1000 个行 Widget；回滚复用缓存 Widget，但 State 仍挂载/最终销毁 1932 次，峰值活跃 State 25，移除后活跃 State 与缓存计数都为 0。
- 向前 960 行的 RSS：原生 168.49 MiB、同步 JS 168.66 MiB、虚拟列表 169.09 MiB。无强制 GC，RSS 包含 Dart/native/GPU 分配器保留；这不是存活堆大小，也不是完整泄漏检测。虚拟列表保留历史 Widget 的策略仍然存在，长距离滚动的缓存上界问题未在本轮修改。

本轮仍没有实际运行 Android、iOS、macOS 或 Linux，也没有浏览器运行时测试；Web 验证是编译验证。源码审核、Windows 回归与简单场景性能复测已完成，IDE 实际启动与业务页面点测仍需人工验收。未提交代码。

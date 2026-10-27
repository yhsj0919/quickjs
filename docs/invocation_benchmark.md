# 核心调用优化基准

以下历史数据在 Future API 默认当前 isolate 的版本采集。0.4.0 的 Future API 默认后台执行，
额外包含 isolate 消息边界；复现历史配置时需显式指定 `JsExecution.currentIsolate`，
不能将这些旧数据当作新默认执行模式的性能结果。

入口 `examples/lemon_js_example/lib/invocation_benchmark.dart`，在 example 目录运行：

```powershell
flutter build windows --release --no-pub --target lib/invocation_benchmark.dart
```

生成的 exe 第一参数为 JSON 输出绝对路径。
每组固定生成 index 0～999 的 1000 个相同行对象，计入 Dart 参数编码、调用、结果编解码，
不计入 Flutter Widget 创建、layout、paint。参数分组在计时前准备，但编码在计时内。
每组预热 3 次，测量 15 次，报告中位数、P90、最小/最大值。
这是 Release CPU 调用基准，不是帧率基准。

2026-10-11 Windows Release 实测，中位数单位为 μs/行：

| 路径 | 单次 | 每批 20 | 每批 100 |
| --- | ---: | ---: | ---: |
| 同步 JS 行函数 | 23.49 | 20.16 | 19.40 |
| Future API，等待 JS 结果 | 29.98 | 22.95 | 21.25 |
| 同步 JS→Dart hostEcho→JS 返回行 | 41.59 | 40.05 | 37.15 |
| Future API，JS→Dart hostEcho→JS 返回行 | 50.20 | 42.62 | 38.64 |

精确值及各组分布见 [原始 JSON](invocation_benchmark_results.json)。
`medianMs` 是生成 1000 行的整体时间；因此数值与 `medianUsPerRow` 相同，但单位不同。
同步纯 JS 批次 20 相对单次约减少 14% 调用成本，异步 API 约减少 23%。
宿主回调成本仍须按行支付，批量合并不能消除这些真实调用，因此其批次收益更小。
本次每批 100 在这些简单函数中更快，但未评估更复杂函数、批次响应延迟和大型结果，不据此设置全局固定批次大小。

最终数据由完整列表基准结束后调用同一个 `measureInvocations()` 采集，没有并行运行测试或编译。

本次数据衡量重构后的直接调用和批量策略之间的差异，没有单独测出旧 callback codec 的优化倍数。
旧同步行生成 0.832 ms/行包含 node parse 与 renderer，不能直接和本表的纯调用数字计算加速倍数。
同场景整条行生成链和真实帧耗时的前后对照见 [列表报告](list_runtime_benchmark.md)。

## 任意源码 eval 包装层优化

同一个 Release 入口增加 `--eval` 参数：

```powershell
./quickjs_example.exe E:/quickjs/build/eval-results.json --eval
```

2026-10-11 Windows Release，每组预热 300 次，15 个样本，每样本 1000 次。
先建立 Dart 原生对象构建基线，再比较直接 call、raw eval、结构化 eval、带临时参数的 eval。
JS 场景均执行 `makeValue(x)`，返回 `{value:x+1}`；raw 仅返回原始字符串，不做结构化转换，
因此其绝对耗时不能与结构化结果直接比较收益。原生基线也不包含跨层和转换成本。
计时包括 Dart 参数构造、编码、编译、执行、结果解码；没有 Widget、帧采样或渲染。
修改前后均在独立 Release 进程运行，没有同时执行测试或编译。

单位 μs/次，均为样本折算单次耗时的中位数：

| 路径 | 修改前 | 修改后 | 修改前/后 P90 |
| --- | ---: | ---: | ---: |
| Dart 对象构建基线 | 0.066 | 0.056 | 0.170 / 0.161 |
| 直接 callSync 对照 | 17.782 | 17.612 | 19.616 / 19.408 |
| 不带参数 evalRawSync 对照 | 4.093 | 4.129 | 4.760 / 4.568 |
| evalSync 结构化结果 | 34.843 | 17.069 | 37.048 / 19.656 |
| evalSync 带临时 globals | 126.951 | 24.382 | 143.545 / 25.764 |

单变量修改是将每次生成、编译的执行包装层移入 Context 预装执行器。
结构化 eval 约快 2.0 倍；带临时参数约快 5.2 倍。直接 call 和无参数 raw 路径保持接近，
支持包装层编译是本次样例的主要额外成本这一结论。用户源码仍然每次编译和执行，
没有字节码缓存、结果缓存或作用域改写。对于重计算或大型源码，实际倍数可能明显不同。

异常源码名称显式传递，保留重复副作用、var/let 求值作用域、异常后临时参数恢复，
测试覆盖 local/worker、结构化字节值、primitive/frozen 异常及同步超时。
精确数据见 [eval 前后原始 JSON](eval_benchmark_results.json)。
此前的列表帧率与内存报告未在这轮 eval 改动后重新采样，不能视为本轮验收数据。

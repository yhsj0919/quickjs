# 原生 Release 构建

`lemon_js` 在 `packages/lemon_js/native/CMakeLists.txt` 统一管理原生优化，
确保各 Flutter 平台采用一致的构建策略。

## Release 优化

- 常规 Release 优化等级由平台工具链决定。当前 MSVC 使用 `/O2`，Android
  NDK 使用 `-O3`；
- 当 `check_ipo_supported()` 检测通过时，`Release`、`RelWithDebInfo` 和
  `MinSizeRel` 默认启用 IPO/LTO；
- 不支持 IPO/LTO 的工具链会安全回退到正常的 Release 优化构建；
- 发布包不会使用 `-march=native` 等绑定构建机器 CPU 的参数。

2026-08-10 在同一台 Windows x64 机器上使用 MSVC、相同 DLL ABI 和相同
Dart 基准进行对照，每种配置运行 5 次：

| 指标 | `/O2` 基线 | `/O2 + /GL + /LTCG` | 结果 |
| --- | ---: | ---: | ---: |
| 已加载模块调用中位数的中位数 | 0.897 ms | 0.896 ms | 无明显变化 |
| 批量 Context 初始化中位数的中位数 | 1.372 ms | 1.303 ms | 降低 5.0% |
| 顺序初始化中位数的中位数 | 1.827 ms | 1.660 ms | 降低 9.1% |
| DLL 大小 | 1,089,536 字节 | 1,068,544 字节 | 减少 1.9% |

模块调用基准主要受 Worker/Isolate 固定边界影响，因此 LTO 不会明显降低该项
开销。各轮 P95 波动较大，不能据此宣称尾延迟获得稳定改善。

## Android 16 KB 内存页

Android 链接 `libquickjs.so` 时显式使用：

```text
-Wl,-z,max-page-size=16384
```

使用 NDK 28.2.13676358 构建 arm64-v8a Release 产物，并通过
`llvm-readelf -lW` 检查后，所有 `LOAD` 段的对齐值均为 `0x4000`。

当前 Android CMake 3.22 的 IPO 探测会错误选择已移除的 `gold` 链接器，因而
无法启用 IPO。Lemon JS 会在该工具链上回退到 NDK 原有的 `-O3`，同时继续保证
16 KB 对齐。升级到能够通过 CMake 能力检查的工具链后，IPO 会自动启用。

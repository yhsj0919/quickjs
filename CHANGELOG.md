## 0.1.1

* 修复 Web 端 callback Promise handle 生命周期问题，避免 `console.*` 连续运行时触发 WASM memory access out of bounds。
* 修复 Web 端 Dart Stream callback 的 async iterator 返回值，避免 `for await` 在第二次 pull 后提前结束。
* 修复 Web 端 `evalAsync` pending jobs pump 与 class binding 连续异步访问卡住的问题。

## 0.1.0

* 集成 QuickJS（原生 FFI + Web WASM）
* 移除 Method Channel / getPlatformVersion 等模板代码
* Web 端基于 quickjs-wasi 实现 `evaluate` 与 `createRuntime`

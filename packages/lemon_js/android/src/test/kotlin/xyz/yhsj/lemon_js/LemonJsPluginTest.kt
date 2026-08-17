package xyz.yhsj.lemon_js

import io.flutter.embedding.engine.plugins.FlutterPlugin
import org.mockito.Mockito
import kotlin.test.Test

internal class LemonJsPluginTest {
    @Test
    fun pluginRegistersWithoutCrashing() {
        val plugin = LemonJsPlugin()
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        plugin.onAttachedToEngine(binding)
        plugin.onDetachedFromEngine(binding)
    }
}

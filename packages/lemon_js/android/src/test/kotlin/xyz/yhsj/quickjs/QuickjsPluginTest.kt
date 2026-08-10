package xyz.yhsj.quickjs

import io.flutter.embedding.engine.plugins.FlutterPlugin
import org.mockito.Mockito
import kotlin.test.Test

internal class QuickjsPluginTest {
    @Test
    fun pluginRegistersWithoutCrashing() {
        val plugin = QuickjsPlugin()
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        plugin.onAttachedToEngine(binding)
        plugin.onDetachedFromEngine(binding)
    }
}

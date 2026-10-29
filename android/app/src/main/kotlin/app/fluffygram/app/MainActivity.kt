package app.fluffygram.app

import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // ROADMAP T51: the phone's own telemetry said `refresh=60.0Hz` on a
        // 120 Hz Pixel. Flutter reads the display's CURRENT refresh rate once,
        // and a Pixel idles its panel at 60, so the engine scheduled every
        // frame at 60 Hz and the timeline could never reach the smoothness the
        // phone is capable of. Pinning the window's display mode asks the panel
        // for its highest refresh mode while we are the focused window, which
        // is the known workaround for the engine's one-shot rate read. Cost:
        // the panel stops downshifting, so the screen uses more battery - the
        // same trade Android's "Smooth display" setting makes.
        selectHighRefreshMode()
        super.onCreate(savedInstanceState)
    }

    /**
     * Ask this window for the display's highest available refresh mode.
     *
     * Telegram plays a viewer video at the panel's high rate:
     * `RefreshRateController.java:227` scans `Display.getSupportedModes()`
     * for the mode with the highest `getRefreshRate()` and asks the window
     * for it (`:269`, through `AndroidUtilities.java:2821-2826`). Our request
     * goes through `WindowManager.LayoutParams.preferredDisplayModeId` +
     * `Window.setAttributes`: `javap` of this build's
     * `platforms/android-37/android.jar` shows `Window` has **no**
     * `setPreferredDisplayModeId` method, so the reflective call this
     * function shipped with (T51, build 3604) died inside its own catch as a
     * swallowed `NoSuchMethodException` and the panel idled at 60 Hz (owner
     * finding, T63.2).
     */
    private fun selectHighRefreshMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }
        val win = window ?: return
        @Suppress("DEPRECATION")
        val display = windowManager.defaultDisplay ?: return
        var best: android.view.Display.Mode? = null
        for (mode in display.supportedModes) {
            val candidate = best
            if (mode.refreshRate >= 90f &&
                (candidate == null || mode.refreshRate > candidate.refreshRate)
            ) {
                best = mode
            }
        }
        val target = best ?: return
        try {
            val modeId = target.modeId
            val lp = win.attributes
            if (lp.preferredDisplayModeId == modeId) {
                return
            }
            lp.preferredDisplayModeId = modeId
            win.attributes = lp
            Log.i(
                "FLUFFYGRAM",
                "preferredDisplayModeId=$modeId " +
                    "${target.physicalWidth}x${target.physicalHeight}@${target.refreshRate}Hz",
            )
        } catch (e: Exception) {
            Log.w("FLUFFYGRAM", "high refresh mode request failed: $e")
        }
    }

    /**
     * Release the window's preferred display mode request (T63.2): back to
     * `preferredDisplayModeId = 0`, no preference, so the panel may downshift
     * again while no video plays. The next video re-requests `high`.
     */
    private fun resetHighRefreshMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return
        }
        val win = window ?: return
        try {
            val lp = win.attributes
            if (lp.preferredDisplayModeId == 0) {
                return
            }
            lp.preferredDisplayModeId = 0
            win.attributes = lp
            Log.i("FLUFFYGRAM", "preferredDisplayModeId reset")
        } catch (e: Exception) {
            Log.w("FLUFFYGRAM", "high refresh mode reset failed: $e")
        }
    }


    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(getApplicationContext())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // T63.2: the viewer's video player asks the window for the panel's
        // high refresh mode while a video plays and releases the request when
        // the page closes (`lib/pages/image_viewer/video_player.dart`).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.fluffygram/display",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "high" -> {
                    selectHighRefreshMode()
                    result.success(null)
                }
                "reset" -> {
                    resetHighRefreshMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Prevent Flutter engine gets destroyed on back button close.
    override fun createFlutterFragment(): FlutterFragment =
        super.createFlutterFragment().apply {
            arguments?.putBoolean("destroy_engine_with_fragment", false)
        }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            return eng
        }

        // Make push services run in the same engine.
        // https://codeberg.org/UnifiedPush/flutter-connector/src/branch/main/unifiedpush_android/android/src/main/kotlin/org/unifiedpush/flutter/connector/UnifiedPushService.kt#L17-L32
        fun provideRunningEngine(context: Context): FlutterEngine {
            var eng = engine
            if (eng == null) {
                eng = provideEngine(context)
                eng.getLocalizationPlugin().sendLocalesToFlutter(
                    context.getResources().getConfiguration())
                eng.getDartExecutor().executeDartEntrypoint(
                    DartEntrypoint.createDefault())
            }
            return eng
        }
    }
}

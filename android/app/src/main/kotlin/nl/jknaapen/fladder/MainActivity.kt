package nl.jknaapen.fladder

import BatteryOptimizationPigeon
import FlutterError
import LocalNetworkPermissionPigeon
import NativeVideoActivity
import PlayerSettingsPigeon
import StartResult
import TranslationsPigeon
import VideoPlayerApi
import VideoPlayerControlsCallback
import VideoPlayerListenerCallback
import android.annotation.SuppressLint
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.net.Uri
import android.util.Log
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import nl.jknaapen.fladder.objects.PlayerSettingsObject
import nl.jknaapen.fladder.objects.TranslationsMessenger
import nl.jknaapen.fladder.objects.VideoPlayerObject
import nl.jknaapen.fladder.utility.leanBackEnabled
import androidx.core.net.toUri
import nl.jknaapen.fladder.wallpaper.WallpaperApi
import nl.jknaapen.fladder.wallpaper.WallpaperApiUtility
import java.io.File
import java.util.Objects

class WallpaperFileProvider : FileProvider()

class MainActivity : AudioServiceFragmentActivity(), NativeVideoActivity {
    private lateinit var videoPlayerLauncher: ActivityResultLauncher<Intent>
    private var videoPlayerCallback: ((Result<StartResult>) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val videoPlayerHost = VideoPlayerObject
        NativeVideoActivity.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )
        WallpaperApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            WallpaperApiUtility(this, wallpaperLauncher)
        )
        VideoPlayerApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            videoPlayerHost.implementation
        )
        videoPlayerHost.videoPlayerListener =
            VideoPlayerListenerCallback(flutterEngine.dartExecutor.binaryMessenger)

        videoPlayerHost.videoPlayerControls =
            VideoPlayerControlsCallback(flutterEngine.dartExecutor.binaryMessenger)

        TranslationsMessenger.translation =
            TranslationsPigeon(flutterEngine.dartExecutor.binaryMessenger)

        PlayerSettingsPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = PlayerSettingsObject
        )

        BatteryOptimizationPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : BatteryOptimizationPigeon {
                override fun isIgnoringBatteryOptimizations(): Boolean {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    return pm.isIgnoringBatteryOptimizations(packageName)
                }

                override fun openBatteryOptimizationSettings() {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        )

        // JT-HOOK: external-intent (vtmGO/GOPlay in de zijbalk, zie lib/jt/jt_streaming_services.dart)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JT_INTENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openIntentUri") {
                    val uri = call.argument<String>("uri")
                    result.success(uri != null && jtOpenIntentUri(uri))
                } else {
                    result.notImplemented()
                }
            }

        LocalNetworkPermissionPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : LocalNetworkPermissionPigeon {
                override fun getAndroidSdkInt(): Long = Build.VERSION.SDK_INT.toLong()
            }
        )

        videoPlayerLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val callback = videoPlayerCallback
            videoPlayerCallback = null

            val startResult = if (result.resultCode == RESULT_OK) {
                StartResult(resultValue = result.data?.getStringExtra("result") ?: "Finished")
            } else {
                StartResult(resultValue = "Cancelled")
            }

            VideoPlayerObject.implementation.player?.stop()
            VideoPlayerObject.implementation.player?.release()
            callback?.invoke(Result.success(startResult))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the Activity's intent is updated so Flutter (and plugins / AutoRoute) receive runtime deep-links.
        setIntent(intent)
    }

    private val wallpaperLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        // Handle the result of the wallpaper intent if needed
    }

    override fun launchActivity(callback: (Result<StartResult>) -> Unit) {
        try {
            videoPlayerCallback = callback
            val intent = Intent(this, VideoPlayerActivity::class.java)
            videoPlayerLauncher.launch(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun disposeActivity() {
        VideoPlayerObject.implementation.player?.stop()
        VideoPlayerObject.implementation.player?.release()
        VideoPlayerObject.currentActivity?.finish()
    }

    override fun isLeanBackEnabled(): Boolean = leanBackEnabled(applicationContext)

    // JT-HOOK: external-intent
    // Opent een intent://-URI zoals een browser dat doet. Lukt dat niet, dan de app
    // gewoon starten (Android TV-launcher eerst), en anders de browser_fallback_url.
    private fun jtOpenIntentUri(uri: String): Boolean {
        val intent = try {
            Intent.parseUri(uri, Intent.URI_INTENT_SCHEME)
        } catch (e: Exception) {
            Log.w(JT_TAG, "Ongeldige intent-URI: $uri", e)
            return false
        }
        intent.selector = null
        intent.component = null
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (jtStart(intent)) return true

        val pkg = intent.`package`
        if (pkg != null) {
            val launch = packageManager.getLeanbackLaunchIntentForPackage(pkg)
                ?: packageManager.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (jtStart(launch)) return true
            }
        }

        val fallback = intent.getStringExtra("browser_fallback_url")
        if (fallback != null) {
            val view = Intent(Intent.ACTION_VIEW, fallback.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (jtStart(view)) return true
        }
        return false
    }

    private fun jtStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        Log.i(JT_TAG, "Kon ${intent} niet starten: ${e.message}")
        false
    }

    companion object {
        private const val JT_INTENT_CHANNEL = "be.jt.streaming/intent"
        private const val JT_TAG = "JtIntent"
    }
}

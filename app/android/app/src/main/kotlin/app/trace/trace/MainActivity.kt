package app.trace.trace

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** Play Integrity standard-request provider, prepared once per process (spec F-17). */
    private var integrity: StandardIntegrityTokenProvider? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.trace/integrity").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val project = call.argument<Number>("cloudProjectNumber")?.toLong()
                        ?: return@setMethodCallHandler result.error("bad_args", "cloudProjectNumber", null)
                    IntegrityManagerFactory.createStandard(applicationContext)
                        .prepareIntegrityToken(PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build())
                        .addOnSuccessListener { integrity = it; result.success(true) }
                        .addOnFailureListener { result.error("prepare_failed", it.message, null) }
                }
                "request" -> {
                    val provider = integrity ?: return@setMethodCallHandler result.error("not_prepared", null, null)
                    val hash = call.argument<String>("requestHash")
                        ?: return@setMethodCallHandler result.error("bad_args", "requestHash", null)
                    provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                        .addOnSuccessListener { result.success(it.token()) }
                        .addOnFailureListener { result.error("request_failed", it.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}

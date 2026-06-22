package com.opencode.mobile

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.opencode.mobile/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getArch" -> {
                    result.success(Build.CPU_ABI)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL_FAILED", e.message, null)
                    }
                }
                "isAppInstalled" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(isAppInstalled(packageName))
                }
                "checkFileExists" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(File(path).exists())
                }
                "setExecutable" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        result.success(File(path).setExecutable(true))
                    } catch (e: Exception) {
                        result.error("SET_EXEC_FAILED", e.message, null)
                    }
                }
                "runTermuxCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    try {
                        runTermuxCommand(command)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TERMUX_FAILED", e.message, null)
                    }
                }
                "runTermuxScript" -> {
                    val scriptPath = call.argument<String>("scriptPath") ?: ""
                    try {
                        runTermuxCommand("bash $scriptPath")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TERMUX_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAppInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun runTermuxCommand(command: String) {
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            setClassName("com.termux", "com.termux.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home")
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}

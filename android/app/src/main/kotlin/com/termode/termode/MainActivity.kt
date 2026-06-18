package com.termode.termode

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.termode/native_shell"
    private var channel: MethodChannel? = null
    
    // Thread-safe mapping of active processes by tab sessionId
    private val activeProcesses = ConcurrentHashMap<String, Process>()
    private val ptyProcesses = ConcurrentHashMap<String, Process>()
    private val realPtyMasterFds = ConcurrentHashMap<String, Int>()
    private val realPtyPids = ConcurrentHashMap<String, Int>()

    private var pendingStorageResult: MethodChannel.Result? = null
    private val FOLDER_PICKER_REQUEST_CODE = 4222

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FOLDER_PICKER_REQUEST_CODE) {
            val result = pendingStorageResult
            pendingStorageResult = null
            if (result != null) {
                if (resultCode == RESULT_OK && data != null) {
                    val uri = data.data
                    if (uri != null) {
                        try {
                            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            contentResolver.takePersistableUriPermission(uri, takeFlags)
                            
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            prefs.edit().putString("linked_uri", uri.toString()).apply()
                            
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            result.error("PERMISSION_ERROR", "Failed to take persistable URI permission: ${e.message}", null)
                        }
                    } else {
                        result.error("PICK_FAILED", "URI was null", null)
                    }
                } else {
                    result.error("CANCELLED", "User cancelled folder picker", null)
                }
            }
        }
    }

    override fun onDestroy() {
        for (masterFd in realPtyMasterFds.values) {
            try {
                nativeClose(masterFd)
            } catch (e: Exception) {
                // ignore
            }
        }
        realPtyMasterFds.clear()

        for (pid in realPtyPids.values) {
            try {
                nativeKillProcessGroup(pid, 9)
            } catch (e: Exception) {
                // ignore
            }
        }
        realPtyPids.clear()

        for (process in ptyProcesses.values) {
            try {
                process.destroyForcibly()
            } catch (e: Exception) {
                // ignore
            }
        }
        ptyProcesses.clear()

        for (process in activeProcesses.values) {
            try {
                process.destroyForcibly()
            } catch (e: Exception) {
                // ignore
            }
        }
        activeProcesses.clear()

        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = mChannel
        mChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "executeCommand" -> {
                    val command = call.argument<String>("command")
                    val sessionId = call.argument<String>("sessionId")
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000

                    if (command != null && sessionId != null) {
                        thread {
                            var process: Process? = null
                            try {
                                val homeDir = java.io.File(filesDir, "home")
                                if (!homeDir.exists()) {
                                    homeDir.mkdirs()
                                }
                                val usrDir = java.io.File(filesDir, "usr")
                                val binDir = java.io.File(filesDir, "usr/bin")
                                val tmpDir = java.io.File(filesDir, "tmp")

                                val pb = ProcessBuilder("/system/bin/sh", "-c", command)
                                pb.directory(homeDir)

                                val env = pb.environment()
                                env["HOME"] = homeDir.absolutePath
                                env["TERMODE_HOME"] = homeDir.absolutePath
                                env["TERMODE_USR"] = usrDir.absolutePath
                                env["TERMODE_BIN"] = binDir.absolutePath
                                env["TERMODE_PREFERRED_CWD"] = homeDir.absolutePath
                                env["TMPDIR"] = tmpDir.absolutePath
                                env["PATH"] = "${binDir.absolutePath}:/system/bin:/system/xbin:/vendor/bin:/product/bin"
                                env["TERM"] = "xterm-256color"

                                process = pb.start()
                                activeProcesses[sessionId] = process

                                var stdout = ""
                                var stderr = ""
                                val maxOutputSize = 50000 // 50KB output protection limit

                                // Stdout reader thread
                                val stdoutThread = thread {
                                    try {
                                        val reader = BufferedReader(InputStreamReader(process.inputStream))
                                        val builder = StringBuilder()
                                        var line: String?
                                        while (reader.readLine().also { line = it } != null) {
                                            if (builder.length + line!!.length + 1 > maxOutputSize) {
                                                builder.append("\n[Output truncated: exceeded limit of ")
                                                       .append(maxOutputSize)
                                                       .append(" characters]\n")
                                                break
                                            }
                                            builder.append(line).append("\n")
                                        }
                                        stdout = builder.toString()
                                    } catch (e: Exception) {
                                        stdout = "Error reading stdout: ${e.message}"
                                    }
                                }

                                // Stderr reader thread
                                val stderrThread = thread {
                                    try {
                                        val reader = BufferedReader(InputStreamReader(process.errorStream))
                                        val builder = StringBuilder()
                                        var line: String?
                                        while (reader.readLine().also { line = it } != null) {
                                            if (builder.length + line!!.length + 1 > maxOutputSize) {
                                                builder.append("\n[Error output truncated: exceeded limit of ")
                                                       .append(maxOutputSize)
                                                       .append(" characters]\n")
                                                break
                                            }
                                            builder.append(line).append("\n")
                                        }
                                        stderr = builder.toString()
                                    } catch (e: Exception) {
                                        stderr = "Error reading stderr: ${e.message}"
                                    }
                                }

                                // Wait for process termination with timeout
                                val finished = process.waitFor(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
                                activeProcesses.remove(sessionId)

                                if (!finished) {
                                    process.destroyForcibly()
                                    stdoutThread.interrupt()
                                    stderrThread.interrupt()

                                    Handler(Looper.getMainLooper()).post {
                                        result.error("TIMEOUT", "Command timed out after $timeoutMs ms", null)
                                    }
                                } else {
                                    stdoutThread.join(500)
                                    stderrThread.join(500)

                                    val exitCode = process.exitValue()
                                    val response = mapOf(
                                        "stdout" to stdout,
                                        "stderr" to stderr,
                                        "exitCode" to exitCode
                                    )

                                    Handler(Looper.getMainLooper()).post {
                                        result.success(response)
                                    }
                                }
                            } catch (e: Exception) {
                                if (process != null) {
                                    activeProcesses.remove(sessionId)
                                }
                                Handler(Looper.getMainLooper()).post {
                                    result.error("EXECUTION_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "Command or sessionId was null", null)
                    }
                }
                "cancelCommand" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId != null) {
                        val process = activeProcesses[sessionId]
                        if (process != null) {
                            process.destroyForcibly()
                            activeProcesses.remove(sessionId)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                    }
                }
                "getDiagnostics" -> {
                    thread {
                        try {
                            val userDir = System.getProperty("user.dir") ?: ""
                            val pathEnv = System.getenv("PATH") ?: ""
                            val uid = android.os.Process.myUid()

                            val runtimeHome = java.io.File(filesDir, "home").absolutePath
                            val binDir = java.io.File(filesDir, "usr/bin").absolutePath
                            val runtimePath = "$binDir:/system/bin:/system/xbin:/vendor/bin:/product/bin"

                            val pathsToCheck = listOf(
                                "/system",
                                "/system/bin",
                                "/system/bin/sh",
                                "/system/bin/toybox",
                                "/system/bin/ls"
                            )
                            val fileChecks = pathsToCheck.map { path ->
                                val file = java.io.File(path)
                                mapOf(
                                    "path" to path,
                                    "exists" to file.exists(),
                                    "canRead" to file.canRead(),
                                    "canExecute" to file.canExecute()
                                )
                            }

                            // Run test command
                            var testOk = false
                            var testOutput = ""
                            try {
                                val proc = ProcessBuilder("/system/bin/sh", "-c", "echo shell-ok").start()
                                val reader = BufferedReader(InputStreamReader(proc.inputStream))
                                val output = reader.readLine()?.trim() ?: ""
                                val finished = proc.waitFor(2, TimeUnit.SECONDS)
                                testOk = finished && proc.exitValue() == 0 && output == "shell-ok"
                                testOutput = if (testOk) "shell-ok" else "failed (exit: ${proc.exitValue()}, out: '$output')"
                            } catch (e: Exception) {
                                testOutput = "error: ${e.message}"
                            }

                            val response = mapOf(
                                "userDir" to userDir,
                                "cwd" to userDir,
                                "pid" to android.os.Process.myPid(),
                                "abi" to android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
                                "pathEnv" to pathEnv,
                                "uid" to uid,
                                "fileChecks" to fileChecks,
                                "testOutput" to testOutput,
                                "runtimeHome" to runtimeHome,
                                "runtimePath" to runtimePath
                            )

                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DIAGNOSTICS_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "getEnv" -> {
                    thread {
                        try {
                            val homeDir = java.io.File(filesDir, "home").absolutePath
                            val usrDir = java.io.File(filesDir, "usr").absolutePath
                            val binDir = java.io.File(filesDir, "usr/bin").absolutePath
                            val tmpDir = java.io.File(filesDir, "tmp").absolutePath
                            val pathVal = "$binDir:/system/bin:/system/xbin:/vendor/bin:/product/bin"

                            // Get the actual runtime pwd of a process
                            var pwdVal = ""
                            try {
                                val proc = ProcessBuilder("/system/bin/sh", "-c", "pwd").apply {
                                    directory(java.io.File(homeDir))
                                    environment().apply {
                                        put("HOME", homeDir)
                                        put("PATH", pathVal)
                                    }
                                }.start()
                                val reader = BufferedReader(InputStreamReader(proc.inputStream))
                                pwdVal = reader.readLine()?.trim() ?: ""
                                proc.waitFor()
                            } catch (e: Exception) {
                                pwdVal = "error: ${e.message}"
                            }

                            val response = mapOf(
                                "HOME" to homeDir,
                                "TERMODE_HOME" to homeDir,
                                "TERMODE_USR" to usrDir,
                                "TERMODE_BIN" to binDir,
                                "TERMODE_PREFERRED_CWD" to pwdVal,
                                "TMPDIR" to tmpDir,
                                "PATH" to pathVal,
                                "workingDirectory" to pwdVal
                            )
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("ENV_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "pickStorageFolder" -> {
                    pendingStorageResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    startActivityForResult(intent, FOLDER_PICKER_REQUEST_CODE)
                }
                "getStorageStatus" -> {
                    val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                    val linkedUriStr = prefs.getString("linked_uri", null)
                    if (linkedUriStr == null) {
                        result.success(null)
                    } else {
                        thread {
                            var displayName: String? = null
                            try {
                                val uri = Uri.parse(linkedUriStr)
                                val docId = DocumentsContract.getTreeDocumentId(uri)
                                val docUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)
                                val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                                contentResolver.query(docUri, projection, null, null, null)?.use { cursor ->
                                    if (cursor.moveToFirst()) {
                                        displayName = cursor.getString(0)
                                    }
                                }
                                val response = mapOf(
                                    "uri" to linkedUriStr,
                                    "displayName" to displayName
                                )
                                Handler(Looper.getMainLooper()).post {
                                    result.success(response)
                                }
                            } catch (e: SecurityException) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("PERMISSION_REVOKED", "Permission revoked or folder access denied: ${e.message}", null)
                                }
                            } catch (e: Exception) {
                                val response = mapOf(
                                    "uri" to linkedUriStr,
                                    "displayName" to null
                                )
                                Handler(Looper.getMainLooper()).post {
                                    result.success(response)
                                }
                            }
                        }
                    }
                }
                "unlinkStorage" -> {
                    val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                    val linkedUriStr = prefs.getString("linked_uri", null)
                    if (linkedUriStr != null) {
                        try {
                            val uri = Uri.parse(linkedUriStr)
                            val releaseFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            contentResolver.releasePersistableUriPermission(uri, releaseFlags)
                        } catch (e: Exception) {
                            // ignore
                        }
                        prefs.edit().remove("linked_uri").apply()
                    }
                    result.success(null)
                }
                "listStorageFiles" -> {
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            
                            val directoryUri = Uri.parse(linkedUriStr)
                            val fileList = mutableListOf<String>()
                            val docId = DocumentsContract.getTreeDocumentId(directoryUri)
                            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(directoryUri, docId)
                            
                            contentResolver.query(
                                childrenUri,
                                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                                null, null, null
                            )?.use { cursor ->
                                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                                while (cursor.moveToNext()) {
                                    if (nameIndex != -1) {
                                        fileList.add(cursor.getString(nameIndex))
                                    }
                                }
                            }
                            
                            Handler(Looper.getMainLooper()).post {
                                result.success(fileList)
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("QUERY_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "readStorageFile" -> {
                    val filename = call.argument<String>("filename")
                    if (filename == null) {
                        result.error("INVALID_ARGUMENTS", "Filename was null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            
                            val directoryUri = Uri.parse(linkedUriStr)
                            val childUri = findChildUri(directoryUri, filename)
                            if (childUri == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("FILE_NOT_FOUND", "File not found: $filename", null)
                                }
                                return@thread
                            }
                            
                            val text = contentResolver.openInputStream(childUri)?.use { inputStream ->
                                inputStream.bufferedReader().use { it.readText() }
                            }
                            
                            Handler(Looper.getMainLooper()).post {
                                result.success(text)
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: java.io.FileNotFoundException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("FILE_NOT_FOUND", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("READ_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "writeStorageFile" -> {
                    val filename = call.argument<String>("filename")
                    val content = call.argument<String>("content")
                    if (filename == null || content == null) {
                        result.error("INVALID_ARGUMENTS", "Filename or content was null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            
                            val directoryUri = Uri.parse(linkedUriStr)
                            var childUri = findChildUri(directoryUri, filename)
                            if (childUri == null) {
                                val docId = DocumentsContract.getTreeDocumentId(directoryUri)
                                val parentUri = DocumentsContract.buildDocumentUriUsingTree(directoryUri, docId)
                                val mimeType = "text/plain"
                                val newUri = DocumentsContract.createDocument(contentResolver, parentUri, mimeType, filename)
                                if (newUri != null) {
                                    childUri = newUri
                                }
                            }
                            
                            if (childUri != null) {
                                contentResolver.openOutputStream(childUri, "w")?.use { outputStream ->
                                    outputStream.bufferedWriter().use { it.write(content) }
                                }
                                Handler(Looper.getMainLooper()).post {
                                    result.success(true)
                                }
                            } else {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("WRITE_ERROR", "Could not resolve or create child file", null)
                                }
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "deleteStorageFile" -> {
                    val filename = call.argument<String>("filename")
                    if (filename == null) {
                        result.error("INVALID_ARGUMENTS", "Filename was null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            val directoryUri = Uri.parse(linkedUriStr)
                            val childUri = findChildUri(directoryUri, filename)
                            if (childUri == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("FILE_NOT_FOUND", "File not found: $filename", null)
                                }
                                return@thread
                            }
                            
                            if (supportsDelete(childUri)) {
                                val deleted = DocumentsContract.deleteDocument(contentResolver, childUri)
                                Handler(Looper.getMainLooper()).post {
                                    result.success(deleted)
                                }
                            } else {
                                Handler(Looper.getMainLooper()).post {
                                    result.success(false)
                                }
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DELETE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "supportsDelete" -> {
                    val filename = call.argument<String>("filename")
                    if (filename == null) {
                        result.error("INVALID_ARGUMENTS", "Filename was null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            val directoryUri = Uri.parse(linkedUriStr)
                            val childUri = findChildUri(directoryUri, filename)
                            if (childUri == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("FILE_NOT_FOUND", "File not found: $filename", null)
                                }
                                return@thread
                            }
                            val canDelete = supportsDelete(childUri)
                            Handler(Looper.getMainLooper()).post {
                                result.success(canDelete)
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("ERROR", e.message, null)
                            }
                        }
                    }
                }
                "createStorageDirectory" -> {
                    val folderName = call.argument<String>("folderName")
                    if (folderName == null) {
                        result.error("INVALID_ARGUMENTS", "FolderName was null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val prefs = getSharedPreferences("termode_storage", Context.MODE_PRIVATE)
                            val linkedUriStr = prefs.getString("linked_uri", null)
                            if (linkedUriStr == null) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("NOT_LINKED", "No linked storage folder", null)
                                }
                                return@thread
                            }
                            val directoryUri = Uri.parse(linkedUriStr)
                            val docId = DocumentsContract.getTreeDocumentId(directoryUri)
                            val parentUri = DocumentsContract.buildDocumentUriUsingTree(directoryUri, docId)
                            val mimeType = DocumentsContract.Document.MIME_TYPE_DIR
                            val newDocId = DocumentsContract.createDocument(contentResolver, parentUri, mimeType, folderName)
                            Handler(Looper.getMainLooper()).post {
                                result.success(newDocId != null)
                            }
                        } catch (e: SecurityException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PERMISSION_REVOKED", e.message, null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("MKDIR_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "nativeTool" -> {
                    val command = call.argument<String>("command") ?: ""
                    val args = call.argument<String>("args") ?: ""
                    thread {
                        try {
                            val response: Map<String, Any?> = when (command) {
                                "info" -> mapOf(
                                    "ok" to true,
                                    "abi" to nativeToolAbi(),
                                    "pid" to nativeToolPid(),
                                    "cwd" to nativeToolCwd()
                                )
                                "echo" -> mapOf("ok" to true, "value" to nativeToolEcho(args))
                                "cwd" -> mapOf("ok" to true, "value" to nativeToolCwd())
                                "pid" -> mapOf("ok" to true, "value" to nativeToolPid())
                                "abi" -> mapOf("ok" to true, "value" to nativeToolAbi())
                                "hash" -> mapOf(
                                    "ok" to true,
                                    "value" to nativeToolHash(args),
                                    "hashType" to "SHA-256"
                                )
                                "time" -> mapOf("ok" to true, "value" to nativeToolTime())
                                "env" -> mapOf("ok" to true, "env" to nativeToolEnvSummary())
                                "doctor" -> mapOf(
                                    "ok" to true,
                                    "abi" to nativeToolAbi(),
                                    "cwd" to nativeToolCwd(),
                                    "echoOk" to (nativeToolEcho("native-tool-doctor") == "native-tool-doctor"),
                                    "hashOk" to (nativeToolHash("x").length == 64)
                                )
                                else -> mapOf(
                                    "ok" to false,
                                    "error" to "unknown native tool command: $command"
                                )
                            }
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("NATIVE_TOOL_FAILED", e.message ?: "Native tool failed", null)
                            }
                        }
                    }
                }
                "jsProof" -> {
                    val command = call.argument<String>("command") ?: ""
                    val args = call.argument<String>("args") ?: ""
                    thread {
                        try {
                            val response: Map<String, Any?> = when (command) {
                                "info" -> mapOf(
                                    "ok" to true,
                                    "engine" to "tiny-js-proof",
                                    "mode" to "native bridge",
                                    "node" to false,
                                    "npm" to false,
                                    "shellExecution" to false,
                                    "status" to "PROOF"
                                )
                                "eval" -> {
                                    val raw = jsProofEvalNative(args)
                                    if (raw.startsWith("OK:")) {
                                        mapOf(
                                            "ok" to true,
                                            "result" to raw.removePrefix("OK:"),
                                            "engine" to "tiny-js-proof",
                                            "mode" to "native bridge"
                                        )
                                    } else {
                                        mapOf(
                                            "ok" to false,
                                            "error" to raw.removePrefix("ERR:"),
                                            "engine" to "tiny-js-proof",
                                            "mode" to "native bridge"
                                        )
                                    }
                                }
                                "doctor" -> mapOf(
                                    "ok" to true,
                                    "bridgeOk" to true,
                                    "evaluatorOk" to (jsProofEvalNative("1 + 2") == "OK:3"),
                                    "errorsOk" to jsProofEvalNative("require('fs')").startsWith("ERR:"),
                                    "engine" to "tiny-js-proof",
                                    "mode" to "native bridge"
                                )
                                "limits" -> mapOf(
                                    "ok" to true,
                                    "engine" to "tiny-js-proof",
                                    "mode" to "native bridge",
                                    "maxCodeLength" to 4096,
                                    "maxFileSize" to 32768
                                )
                                else -> mapOf(
                                    "ok" to false,
                                    "error" to "unknown js proof command: $command",
                                    "engine" to "tiny-js-proof",
                                    "mode" to "native bridge"
                                )
                            }
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("JS_PROOF_FAILED", e.message ?: "JS proof failed", null)
                            }
                        }
                    }
                }
                "quickJs" -> {
                    val command = call.argument<String>("command") ?: ""
                    thread {
                        try {
                            val base = mapOf(
                                "engine" to "QuickJS",
                                "mode" to "native embedded engine",
                                "limited" to true,
                                "node" to false,
                                "npm" to false,
                                "filesystem" to false,
                                "network" to false,
                                "timeout" to false
                            )
                            val response: Map<String, Any?> = when (command) {
                                "info" -> base + mapOf(
                                    "ok" to true,
                                    "status" to "UNAVAILABLE",
                                    "error" to "QuickJS source is not integrated in this build."
                                )
                                "eval" -> base + mapOf(
                                    "ok" to false,
                                    "status" to "UNAVAILABLE",
                                    "error" to "QuickJS engine is not integrated in this build."
                                )
                                "doctor" -> base + mapOf(
                                    "ok" to true,
                                    "bridgeOk" to true,
                                    "engineOk" to false,
                                    "evalOk" to false,
                                    "errorsOk" to true,
                                    "overall" to "LIMITED"
                                )
                                "limits" -> base + mapOf(
                                    "ok" to true,
                                    "maxCodeLength" to 4096,
                                    "maxFileSize" to 32768,
                                    "maxOutputLength" to 8192
                                )
                                else -> base + mapOf(
                                    "ok" to false,
                                    "error" to "unknown QuickJS command: $command"
                                )
                            }
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("QUICKJS_FAILED", e.message ?: "QuickJS probe failed", null)
                            }
                        }
                    }
                }
                "duktape" -> {
                    val command = call.argument<String>("command") ?: ""
                    thread {
                        try {
                            val base = mapOf(
                                "engine" to "Duktape",
                                "mode" to "native embedded engine",
                                "limited" to true,
                                "node" to false,
                                "npm" to false,
                                "filesystem" to false,
                                "network" to false,
                                "timeout" to false
                            )
                            val response: Map<String, Any?> = when (command) {
                                "info" -> base + mapOf(
                                    "ok" to true,
                                    "status" to "UNAVAILABLE",
                                    "error" to "Duktape source is not integrated in this build."
                                )
                                "eval" -> base + mapOf(
                                    "ok" to false,
                                    "status" to "UNAVAILABLE",
                                    "error" to "Duktape engine is not integrated in this build."
                                )
                                "doctor" -> base + mapOf(
                                    "ok" to true,
                                    "bridgeOk" to true,
                                    "engineOk" to false,
                                    "evalOk" to false,
                                    "errorsOk" to true,
                                    "overall" to "LIMITED"
                                )
                                "limits" -> base + mapOf(
                                    "ok" to true,
                                    "maxCodeLength" to 4096,
                                    "maxFileSize" to 32768,
                                    "maxOutputLength" to 8192
                                )
                                else -> base + mapOf(
                                    "ok" to false,
                                    "error" to "unknown Duktape command: $command"
                                )
                            }
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DUKTAPE_FAILED", e.message ?: "Duktape probe failed", null)
                            }
                        }
                    }
                }
                "bundledRuntimeProof" -> {
                    thread {
                        try {
                            // Call into the bundled native library. No external
                            // process is launched and no files are written.
                            val token = try {
                                nativeProofToken()
                            } catch (e: Throwable) {
                                ""
                            }
                            val echo = try {
                                nativeEchoProof("echo hello")
                            } catch (e: Throwable) {
                                ""
                            }
                            val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
                            val pid = android.os.Process.myPid()
                            val cwd = System.getProperty("user.dir") ?: ""
                            val bridgeOk = token == "termode-native-proof-ok"

                            val response = mapOf(
                                "token" to token,
                                "echo" to echo,
                                "abi" to (if (abi.isNotEmpty()) abi else "unknown"),
                                "pid" to pid,
                                "cwd" to cwd,
                                "nativeBridge" to bridgeOk,
                                "apkNativeLayer" to "available"
                            )
                            Handler(Looper.getMainLooper()).post {
                                result.success(response)
                            }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PROOF_FAILED", e.message ?: "Native proof failed", null)
                            }
                        }
                    }
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("INVALID_ARGUMENTS", "URL was null", null)
                        return@setMethodCallHandler
                    }
                    val parsed = try {
                        Uri.parse(url)
                    } catch (e: Exception) {
                        null
                    }
                    val scheme = parsed?.scheme?.lowercase()
                    if (parsed == null || (scheme != "http" && scheme != "https")) {
                        result.error("UNSAFE_URL", "Only http and https URLs can be opened", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, parsed)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message ?: "Could not open URL", null)
                    }
                }
                "ptyStart" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    if (ptyProcesses.containsKey(sessionId)) {
                        val existingProcess = ptyProcesses[sessionId]
                        val isAlive = try {
                            existingProcess?.exitValue()
                            false
                        } catch (e: IllegalThreadStateException) {
                            true
                        }
                        if (isAlive) {
                            result.success(false)
                            return@setMethodCallHandler
                        } else {
                            ptyProcesses.remove(sessionId)
                        }
                    }

                    try {
                        val homeDir = java.io.File(filesDir, "home")
                        if (!homeDir.exists()) {
                            homeDir.mkdirs()
                        }
                        val usrDir = java.io.File(filesDir, "usr")
                        val binDir = java.io.File(filesDir, "usr/bin")
                        val tmpDir = java.io.File(filesDir, "tmp")
                        if (!tmpDir.exists()) {
                            tmpDir.mkdirs()
                        }

                        val pb = ProcessBuilder("/system/bin/sh")
                        pb.directory(homeDir)
                        val env = pb.environment()
                        env["HOME"] = homeDir.absolutePath
                        env["TERMODE_HOME"] = homeDir.absolutePath
                        env["TERMODE_USR"] = usrDir.absolutePath
                        env["TERMODE_BIN"] = binDir.absolutePath
                        env["TMPDIR"] = tmpDir.absolutePath
                        env["PATH"] = "${binDir.absolutePath}:/system/bin:/system/xbin:/vendor/bin:/product/bin"
                        env["TERM"] = "xterm-256color"
                        env["ENV"] = java.io.File(usrDir, "termode-shell-helpers.sh").absolutePath

                        val process = pb.start()
                        ptyProcesses[sessionId] = process

                        // Stdout reader
                        thread {
                            try {
                                val inputStream = process.inputStream
                                val buffer = ByteArray(1024)
                                var bytesRead: Int
                                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                    val text = String(buffer, 0, bytesRead, Charsets.UTF_8)
                                    Handler(Looper.getMainLooper()).post {
                                        channel?.invokeMethod("ptyOutput", mapOf("sessionId" to sessionId, "output" to text))
                                    }
                                }
                            } catch (e: Exception) {
                                // ignore
                            }
                        }

                        // Stderr reader
                        thread {
                            try {
                                val errorStream = process.errorStream
                                val buffer = ByteArray(1024)
                                var bytesRead: Int
                                while (errorStream.read(buffer).also { bytesRead = it } != -1) {
                                    val text = String(buffer, 0, bytesRead, Charsets.UTF_8)
                                    Handler(Looper.getMainLooper()).post {
                                        channel?.invokeMethod("ptyOutput", mapOf("sessionId" to sessionId, "output" to text))
                                    }
                                }
                            } catch (e: Exception) {
                                // ignore
                            }
                        }

                        // Exit waiter
                        thread {
                            try {
                                process.waitFor()
                            } catch (e: Exception) {
                                // ignore
                            } finally {
                                ptyProcesses.remove(sessionId)
                                Handler(Looper.getMainLooper()).post {
                                    channel?.invokeMethod("ptyExit", mapOf("sessionId" to sessionId))
                                }
                            }
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PTY_START_FAILED", e.message, null)
                    }
                }
                "ptyStatus" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val process = ptyProcesses[sessionId]
                    if (process != null) {
                        val isAlive = try {
                            process.exitValue()
                            false
                        } catch (e: IllegalThreadStateException) {
                            true
                        }
                        if (isAlive) {
                            val pid = getProcessId(process)
                            result.success(mapOf("running" to true, "pid" to pid))
                        } else {
                            ptyProcesses.remove(sessionId)
                            result.success(mapOf("running" to false, "pid" to -1))
                        }
                    } else {
                        result.success(mapOf("running" to false, "pid" to -1))
                    }
                }
                "ptyStop" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val process = ptyProcesses[sessionId]
                    if (process != null) {
                        process.destroyForcibly()
                        ptyProcesses.remove(sessionId)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "ptySend" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val text = call.argument<String>("text")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    if (text == null) {
                        result.error("INVALID_ARGUMENTS", "Text was null", null)
                        return@setMethodCallHandler
                    }
                    val process = ptyProcesses[sessionId]
                    if (process == null) {
                        result.error("NOT_RUNNING", "No active PTY process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    val isAlive = try {
                        process.exitValue()
                        false
                    } catch (e: IllegalThreadStateException) {
                        true
                    }
                    if (!isAlive) {
                        ptyProcesses.remove(sessionId)
                        result.error("NOT_RUNNING", "PTY process is not running", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val os = process.outputStream
                            os.write((text + "\n").toByteArray(Charsets.UTF_8))
                            os.flush()
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "ptySendCtrlC" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val process = ptyProcesses[sessionId]
                    if (process == null) {
                        result.error("NOT_RUNNING", "No active shell process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    val isAlive = try {
                        process.exitValue()
                        false
                    } catch (e: IllegalThreadStateException) {
                        true
                    }
                    if (!isAlive) {
                        ptyProcesses.remove(sessionId)
                        result.error("NOT_RUNNING", "Shell process is not running", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val os = process.outputStream
                            os.write(3) // ASCII 3 is Ctrl-C (ETX)
                            os.flush()
                            
                            val pid = getProcessId(process)
                            if (pid != -1) {
                                android.os.Process.sendSignal(pid, 2) // Send SIGINT (2)
                            }
                            
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "ptySendCtrlD" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val process = ptyProcesses[sessionId]
                    if (process == null) {
                        result.error("NOT_RUNNING", "No active shell process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    val isAlive = try {
                        process.exitValue()
                        false
                    } catch (e: IllegalThreadStateException) {
                        true
                    }
                    if (!isAlive) {
                        ptyProcesses.remove(sessionId)
                        result.error("NOT_RUNNING", "Shell process is not running", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val os = process.outputStream
                            os.write(4) // ASCII 4 is Ctrl-D (EOF)
                            os.flush()
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "realPtyStart" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    if (realPtyMasterFds.containsKey(sessionId)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    if (realPtyMasterFds.isNotEmpty()) {
                        result.error("LIMIT_EXCEEDED", "Termode currently limits native PTY prototype to 1 active session globally.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val homeDir = java.io.File(filesDir, "home")
                        if (!homeDir.exists()) {
                            homeDir.mkdirs()
                        }
                        val usrDir = java.io.File(filesDir, "usr")
                        val binDir = java.io.File(filesDir, "usr/bin")
                        val tmpDir = java.io.File(filesDir, "tmp")
                        if (!tmpDir.exists()) {
                            tmpDir.mkdirs()
                        }
                        val requestedWorkingDir = call.argument<String>("workingDirectory")
                        val workingDir = if (requestedWorkingDir != null) {
                            val candidate = java.io.File(requestedWorkingDir).canonicalFile
                            val homeCanonical = homeDir.canonicalFile
                            if (candidate.exists() && candidate.isDirectory && candidate.path.startsWith(homeCanonical.path)) {
                                candidate
                            } else {
                                homeDir
                            }
                        } else {
                            homeDir
                        }
                        val pathEnv = "${binDir.absolutePath}:/system/bin:/system/xbin:/vendor/bin:/product/bin"

                        val cols = call.argument<Int>("cols") ?: 80
                        val rows = call.argument<Int>("rows") ?: 24

                        val ptyInfo = nativeStartPty(
                            homeDir.absolutePath,
                            workingDir.absolutePath,
                            usrDir.absolutePath,
                            binDir.absolutePath,
                            tmpDir.absolutePath,
                            pathEnv,
                            arrayOf("PS1", "ENV", "TERMODE_PROJECTS", "TERMODE_PREFERRED_CWD"),
                            arrayOf(
                                "termode:\$ ",
                                java.io.File(usrDir, "termode-shell-helpers.sh").absolutePath,
                                java.io.File(homeDir, "projects").absolutePath,
                                workingDir.absolutePath
                            ),
                            cols,
                            rows
                        )

                        val masterFd = ptyInfo[0]
                        val pid = ptyInfo[1]

                        if (masterFd < 0 || pid < 0) {
                            val errorMsg = when (masterFd) {
                                -1 -> "PTY allocation failure: open(\"/dev/ptmx\") failed"
                                -2 -> "PTY allocation failure: grantpt() failed"
                                -3 -> "PTY allocation failure: unlockpt() failed"
                                -4 -> "PTY allocation failure: ptsname() failed"
                                -5 -> "PTY allocation failure: fork() failed"
                                else -> "Failed to allocate pseudo-terminal. Code: $masterFd"
                            }
                            result.error("PTY_ALLOCATION_FAILED", errorMsg, null)
                            return@setMethodCallHandler
                        }

                        realPtyMasterFds[sessionId] = masterFd
                        realPtyPids[sessionId] = pid

                        // Read thread
                        thread {
                            try {
                                val buffer = ByteArray(1024)
                                while (true) {
                                    val currentFd = realPtyMasterFds[sessionId] ?: break
                                    val bytesRead = nativeRead(currentFd, buffer)
                                    if (bytesRead <= 0) {
                                        break
                                    }
                                    val text = String(buffer, 0, bytesRead, Charsets.UTF_8)
                                    Handler(Looper.getMainLooper()).post {
                                        channel?.invokeMethod("realPtyOutput", mapOf("sessionId" to sessionId, "output" to text))
                                    }
                                    try {
                                        Thread.sleep(5)
                                    } catch (ex: InterruptedException) {
                                        break
                                    }
                                }
                            } catch (e: Exception) {
                                // ignore
                            } finally {
                                val currentFd = realPtyMasterFds.remove(sessionId)
                                val currentPid = realPtyPids.remove(sessionId)
                                if (currentFd != null) {
                                    nativeClose(currentFd)
                                }
                                if (currentFd != null || currentPid != null) {
                                    Handler(Looper.getMainLooper()).post {
                                        channel?.invokeMethod("realPtyExit", mapOf("sessionId" to sessionId))
                                    }
                                }
                            }
                        }

                        // Exit waiter thread (Zombie process reaper)
                        thread {
                            try {
                                nativeWaitPid(pid)
                            } catch (e: Exception) {
                                // ignore
                            } finally {
                                val currentFd = realPtyMasterFds.remove(sessionId)
                                val currentPid = realPtyPids.remove(sessionId)
                                if (currentFd != null) {
                                    nativeClose(currentFd)
                                }
                                if (currentFd != null || currentPid != null) {
                                    Handler(Looper.getMainLooper()).post {
                                        channel?.invokeMethod("realPtyExit", mapOf("sessionId" to sessionId))
                                    }
                                }
                            }
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PTY_START_FAILED", e.message, null)
                    }
                }
                "realPtyStatus" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    val pid = realPtyPids[sessionId]
                    if (masterFd != null && pid != null) {
                        result.success(mapOf("running" to true, "pid" to pid))
                    } else {
                        result.success(mapOf("running" to false, "pid" to -1))
                    }
                }
                "realPtyResize" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val cols = call.argument<Int>("cols")
                    val rows = call.argument<Int>("rows")
                    if (sessionId == null || cols == null || rows == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID, cols, or rows was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    if (masterFd != null) {
                        val success = nativeResizePty(masterFd, cols, rows)
                        result.success(success)
                    } else {
                        result.error("NOT_RUNNING", "No active real PTY process found for session $sessionId", null)
                    }
                }
                "realPtyStop" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds.remove(sessionId)
                    val pid = realPtyPids.remove(sessionId)
                    if (masterFd != null) {
                        nativeClose(masterFd)
                        if (pid != null) {
                            try {
                                nativeKillProcessGroup(pid, 9)
                            } catch (e: Exception) {
                                // ignore
                            }
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "realPtySend" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val text = call.argument<String>("text")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    if (text == null) {
                        result.error("INVALID_ARGUMENTS", "Text was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    if (masterFd == null) {
                        result.error("NOT_RUNNING", "No active real PTY process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val data = (text + "\n").toByteArray(Charsets.UTF_8)
                            val written = nativeWrite(masterFd, data)
                            Handler(Looper.getMainLooper()).post {
                                result.success(written >= 0)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "realPtySendRaw" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val text = call.argument<String>("text")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    if (text == null) {
                        result.error("INVALID_ARGUMENTS", "Text was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    if (masterFd == null) {
                        result.error("NOT_RUNNING", "No active real PTY process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val data = text.toByteArray(Charsets.UTF_8)
                            val written = nativeWrite(masterFd, data)
                            Handler(Looper.getMainLooper()).post {
                                result.success(written >= 0)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "realPtySendCtrlC" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    if (masterFd == null) {
                        result.error("NOT_RUNNING", "No active real PTY process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            nativeWrite(masterFd, byteArrayOf(3))
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "realPtySendCtrlD" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId == null) {
                        result.error("INVALID_ARGUMENTS", "Session ID was null", null)
                        return@setMethodCallHandler
                    }
                    val masterFd = realPtyMasterFds[sessionId]
                    if (masterFd == null) {
                        result.error("NOT_RUNNING", "No active real PTY process found for session $sessionId", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            nativeWrite(masterFd, byteArrayOf(4))
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("WRITE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun supportsDelete(childUri: Uri): Boolean {
        try {
            val projection = arrayOf(DocumentsContract.Document.COLUMN_FLAGS)
            contentResolver.query(childUri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val flags = cursor.getInt(0)
                    return (flags and DocumentsContract.Document.FLAG_SUPPORTS_DELETE) != 0
                }
            }
        } catch (e: Exception) {
            // ignore
        }
        return false
    }

    private fun findChildUri(directoryUri: Uri, filename: String): Uri? {
        val docId = DocumentsContract.getTreeDocumentId(directoryUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(directoryUri, docId)
        
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (idIndex != -1 && nameIndex != -1) {
                    val name = cursor.getString(nameIndex)
                    if (name == filename) {
                        val childId = cursor.getString(idIndex)
                        return DocumentsContract.buildDocumentUriUsingTree(directoryUri, childId)
                    }
                }
            }
        }
        return null
    }

    private fun getProcessId(process: Process): Int {
        try {
            val pidMethod = process.javaClass.getMethod("pid")
            return (pidMethod.invoke(process) as Long).toInt()
        } catch (e: Exception) {
            try {
                val field = process.javaClass.getDeclaredField("pid")
                field.isAccessible = true
                return field.getInt(process)
            } catch (ex: Exception) {
                return -1
            }
        }
    }

    private external fun nativeStartPty(
        homeDir: String,
        workingDir: String,
        usrDir: String,
        binDir: String,
        tmpDir: String,
        pathEnv: String,
        envKeys: Array<String>,
        envValues: Array<String>,
        cols: Int,
        rows: Int
    ): IntArray

    private external fun nativeResizePty(fd: Int, cols: Int, rows: Int): Boolean
    private external fun nativeKillProcessGroup(pid: Int, sig: Int): Boolean
    private external fun nativeWaitPid(pid: Int): Int

    private external fun nativeRead(fd: Int, buffer: ByteArray): Int
    private external fun nativeWrite(fd: Int, data: ByteArray): Int
    private external fun nativeClose(fd: Int)

    // Bundled runtime proof (v0.28)
    private external fun nativeProofToken(): String
    private external fun nativeEchoProof(input: String): String

    // Tiny native tool proof (v0.29)
    private external fun nativeToolEcho(input: String): String
    private external fun nativeToolCwd(): String
    private external fun nativeToolPid(): Int
    private external fun nativeToolAbi(): String
    private external fun nativeToolHash(input: String): String
    private external fun nativeToolTime(): Long

    // Tiny JS proof (v0.31)
    private external fun jsProofEvalNative(input: String): String
    private external fun jsProofDoctorNative(): Boolean

    // Builds a safe, limited environment summary. Only a fixed whitelist of
    // keys is exposed; nothing else from the process environment is returned.
    private fun nativeToolEnvSummary(): Map<String, String> {
        val homeDir = java.io.File(filesDir, "home").absolutePath
        val usrDir = java.io.File(filesDir, "usr").absolutePath
        val binDir = java.io.File(filesDir, "usr/bin").absolutePath
        val tmpDir = java.io.File(filesDir, "tmp").absolutePath
        return mapOf(
            "HOME" to (System.getenv("HOME") ?: homeDir),
            "TMPDIR" to (System.getenv("TMPDIR") ?: tmpDir),
            "TERMODE_HOME" to homeDir,
            "TERMODE_USR" to usrDir,
            "TERMODE_BIN" to binDir
        )
    }

    companion object {
        init {
            System.loadLibrary("termode_pty")
        }
    }
}

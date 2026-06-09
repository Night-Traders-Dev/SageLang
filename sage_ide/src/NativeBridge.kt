package com.sage.ide

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.concurrent.Executors

class NativeBridge(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()

    fun getExecutablePath(): String {
        val binDir = File(context.filesDir, "bin")
        if (!binDir.exists()) binDir.mkdirs()
        return File(binDir, "sage").absolutePath
    }

    fun prepareCompiler() {
        val executablePath = getExecutablePath()
        val file = File(executablePath)
        
        // Always extract for now to ensure we have the latest version
        try {
            context.assets.open("sage").use { input ->
                FileOutputStream(file).use { output ->
                    input.copyTo(output)
                }
            }
            file.setExecutable(true)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun runSage(sourceCode: String, onOutput: (String) -> Unit) {
        executor.execute {
            try {
                // Write source code to a temporary file
                val sourceFile = File(context.cacheDir, "input.sage")
                sourceFile.writeText(sourceCode)

                val process = ProcessBuilder(getExecutablePath(), sourceFile.absolutePath)
                    .redirectErrorStream(true)
                    .start()

                process.inputStream.bufferedReader().use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        onOutput(line!! + "\n")
                    }
                }
                process.waitFor()
            } catch (e: Exception) {
                onOutput("Error: ${e.message}\n")
            }
        }
    }
}

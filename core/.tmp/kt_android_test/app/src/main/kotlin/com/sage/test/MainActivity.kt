package com.sage.test

import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import sage.runtime.*
import sage.runtime.SageRuntime as S
import java.io.ByteArrayOutputStream
import java.io.PrintStream

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val capture = ByteArrayOutputStream()
        val oldOut = System.out
        System.setOut(PrintStream(capture))
        try { main() }
        catch (e: Exception) { capture.write("Error: ${e.message}".toByteArray()) }
        finally { System.setOut(oldOut) }

        val tv = TextView(this).apply {
            text = capture.toString()
            textSize = 16f
            setPadding(32, 32, 32, 32)
            setTextIsSelectable(true)
        }
        val scroll = ScrollView(this).apply { addView(tv) }
        setContentView(scroll)
    }
}

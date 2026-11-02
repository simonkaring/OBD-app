package com.simonkaring.voltlink.okf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * The Android half of the OKF gate. `./gradlew testDebugUnitTest` fails when `android/knowledge`
 * drifts from the Kotlin sources; regeneration is the same test with `-Pokf.export=true`.
 */
class KnowledgeBundleTest {
    private val projectDir: File? = System.getProperty("okf.root")?.let(::File)
    private val assets: File? = System.getProperty("okf.assets")?.let(::File)
    private val isExport = System.getProperty("okf.export") == "true"

    private fun bundleDir(): File {
        val root = projectDir ?: error(
            "okf.root is not set; run this through Gradle (./gradlew testDebugUnitTest) so the " +
                "bundle paths resolve.",
        )
        val assetsDir = assets ?: error("okf.assets is not set; run this through Gradle.")
        KnowledgeBundle.installAssets(assetsDir)
        return File(root, "knowledge")
    }

    @Test
    fun bundleMatchesItsSources() {
        assumeFalse("regenerating the bundle", isExport)
        val bundle = bundleDir()

        val issues = KnowledgeBundle.check(bundle, assets!!)
        assertTrue(
            "android/knowledge is out of date:\n" + issues.joinToString("\n") +
                "\n\nRun ./gradlew testDebugUnitTest --tests '*KnowledgeBundleTest' -Pokf.export=true",
            issues.isEmpty(),
        )
    }

    @Test
    fun exportRewritesTheBundle() {
        assumeTrue("only when -Pokf.export=true", isExport)
        val bundle = bundleDir()

        val result = KnowledgeBundle.write(bundle, assets!!)
        assertEquals(emptyList<String>(), KnowledgeBundle.check(bundle, assets))
        assertTrue("export wrote nothing", result.written.isNotEmpty())
    }
}

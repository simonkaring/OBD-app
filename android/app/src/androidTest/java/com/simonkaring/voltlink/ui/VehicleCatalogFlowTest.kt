package com.simonkaring.voltlink.ui

import android.Manifest
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import com.simonkaring.voltlink.MainActivity
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import com.simonkaring.voltlink.ui.settings.CATALOG_SEARCH_TAG
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Catalog picker flow: brands are browsed down through model family and model year to a variant,
 * and the search field flattens that tree. The brands used stay in the first screenful of the
 * 69-brand list, so the test never depends on scroll position.
 */
@RunWith(AndroidJUnit4::class)
class VehicleCatalogFlowTest {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<MainActivity>()

    private fun awaitText(text: String) {
        rule.waitUntil(timeoutMillis = 20_000) {
            rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun awaitClosed() {
        rule.waitUntil(timeoutMillis = 10_000) {
            rule.onAllNodesWithText("Choose vehicle").fetchSemanticsNodes().isEmpty()
        }
    }

    private fun openCatalog() {
        awaitText("Settings")
        rule.onNodeWithText("Settings").performClick()
        awaitText("Browse vehicle catalog")
        rule.onNodeWithText("Browse vehicle catalog").performClick()
        awaitText("Choose vehicle")
    }

    /** Leaves the default demo vehicle selected so later suites capture the usual dashboard. */
    @After
    fun restoreDefaultVehicle() {
        val app = rule.activity.application as VoltLinkApplication
        app.vehicleData.selectProfile(VehicleProfileId.MERCEDES_EQ_A250)
    }

    @Test
    fun drillsFromBrandThroughModelYearToVariant() {
        openCatalog()

        // Audi's A6 e-tron has three variants, so the year step is offered.
        rule.onNodeWithText("Audi").performClick()
        awaitText("A6 e-tron")
        rule.onNodeWithText("A6 e-tron").performClick()

        awaitText("Model year")
        awaitText("2025")
        rule.onNodeWithText("2025").performClick()

        awaitText("A6 E Tron Base")
        rule.onNodeWithText("A6 E Tron Base").performClick()

        awaitClosed()
        rule.onNodeWithText("Audi A6 E Tron Base").assertIsDisplayed()
    }

    @Test
    fun singleVariantFamiliesSkipTheYearStep() {
        openCatalog()

        rule.onNodeWithText("Aiways").performClick()
        awaitText("U5")
        rule.onNodeWithText("U5").performClick()

        // Straight to the variant: no "Model year" screen for a one-variant model. The screen
        // title is also "U5", so click the row rather than the heading.
        awaitText("U5")
        rule.waitUntil(timeoutMillis = 5_000) {
            rule.onAllNodesWithText("Model year").fetchSemanticsNodes().isEmpty()
        }
        rule.onNode(hasText("U5") and hasClickAction()).performClick()

        awaitClosed()
        rule.onNodeWithText("Aiways U5").assertIsDisplayed()
    }

    @Test
    fun searchFlattensTheTreeToMatchingVehicles() {
        openCatalog()

        rule.onNodeWithTag(CATALOG_SEARCH_TAG).performTextInput("aiways")
        awaitText("U5")
        // The result row carries the brand, since the tree below it is skipped.
        rule.onNodeWithText("Aiways").assertIsDisplayed()
        rule.onNodeWithText("U5").performClick()

        awaitClosed()
        rule.onNodeWithText("Aiways U5").assertIsDisplayed()
    }
}

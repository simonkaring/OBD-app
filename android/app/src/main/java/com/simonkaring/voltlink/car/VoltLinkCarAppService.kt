package com.simonkaring.voltlink.car

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Entry point for Android Auto and Android Automotive OS: the car-side live telemetry and charging
 * tabs, equivalent to the iOS CarPlay dashboard.
 *
 * Content is read-only and rendered from the same
 * [com.simonkaring.voltlink.services.VehicleDataManager] snapshot and
 * [com.simonkaring.voltlink.services.ChargingTracker] session the phone UI uses, so nothing extra
 * is polled while driving.
 */
class VoltLinkCarAppService : CarAppService() {
    /** The template host is authenticated by the car app library; no extra allow-list applies. */
    override fun createHostValidator(): HostValidator = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = VoltLinkCarSession()
}

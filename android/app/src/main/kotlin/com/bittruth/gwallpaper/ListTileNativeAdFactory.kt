package com.bittruth.gwallpaper

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import com.google.android.gms.ads.nativead.MediaView
import com.bittruth.gwallpaper.R

class ListTileNativeAdFactory(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: Map<String, Any>?
    ): NativeAdView {
        val nativeAdView = LayoutInflater.from(context)
            .inflate(R.layout.list_tile_native_ad, null) as NativeAdView

        with(nativeAdView) {
            val mediaView = findViewById<MediaView>(R.id.ad_media)
            this.mediaView = mediaView

            val iconView = findViewById<ImageView>(R.id.ad_app_icon)
            val icon = nativeAd.icon
            if (icon != null) {
                iconView.setImageDrawable(icon.drawable)
                this.iconView = iconView
            }

            val headlineView = findViewById<TextView>(R.id.ad_headline)
            headlineView.text = nativeAd.headline
            this.headlineView = headlineView

            val bodyView = findViewById<TextView>(R.id.ad_body)
            with(bodyView) {
                text = nativeAd.body
                visibility = if (nativeAd.body.isNullOrEmpty()) android.view.View.INVISIBLE else android.view.View.VISIBLE
            }
            this.bodyView = bodyView

            val ctaView = findViewById<Button>(R.id.ad_call_to_action)
            with(ctaView) {
                 text = nativeAd.callToAction
                 visibility = if (nativeAd.callToAction.isNullOrEmpty()) android.view.View.INVISIBLE else android.view.View.VISIBLE
            }
            this.callToActionView = ctaView
            
            setNativeAd(nativeAd)
        }

        return nativeAdView
    }
}

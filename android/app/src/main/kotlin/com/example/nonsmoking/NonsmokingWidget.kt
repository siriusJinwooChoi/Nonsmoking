package com.cjw.nonsmoking

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.Locale

/**
 * 홈 화면 위젯: 금연 시간, 절약 금액, 안 피운 담배, 폐 건강 표시
 * Flutter SharedPreferences(FlutterSharedPreferences)에서 데이터를 읽어 표시합니다.
 */
class NonsmokingWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val widgetPrefs = context.getSharedPreferences(WIDGET_PREFS_NAME, Context.MODE_PRIVATE)
        var startTimeMs = widgetPrefs.getLong(KEY_START_TIME, -1L).takeIf { it > 0 }
        var dailyCigarettes = widgetPrefs.getInt(KEY_DAILY_CIGS, -1)
        var cigarettesPerPack = widgetPrefs.getInt(KEY_CIGS_PER_PACK, -1)
        var pricePerPack = widgetPrefs.getInt(KEY_PRICE_PER_PACK, -1)
        var lungHealth = widgetPrefs.getInt(KEY_LUNG_HEALTH, -1)

        if (startTimeMs == null || startTimeMs < 0) {
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            startTimeMs = flutterPrefs.getLong(FLUTTER_KEY_START_TIME, -1L).takeIf { it > 0 }
                ?: flutterPrefs.getInt(FLUTTER_KEY_START_TIME, -1).toLong().takeIf { it > 0 } ?: -1L
            if (dailyCigarettes < 0) dailyCigarettes = getPrefInt(flutterPrefs, FLUTTER_KEY_DAILY_CIGS, 0)
            if (cigarettesPerPack < 0) cigarettesPerPack = getPrefInt(flutterPrefs, FLUTTER_KEY_CIGS_PER_PACK, 20)
            if (pricePerPack < 0) pricePerPack = getPrefInt(flutterPrefs, FLUTTER_KEY_PRICE_PER_PACK, 4500)
            if (lungHealth < 0) lungHealth = getPrefInt(flutterPrefs, FLUTTER_KEY_LUNG_HEALTH, 100)
        } else {
            if (dailyCigarettes < 0) dailyCigarettes = 0
            if (cigarettesPerPack < 0) cigarettesPerPack = 20
            if (pricePerPack < 0) pricePerPack = 4500
            if (lungHealth < 0) lungHealth = 100
        }
        lungHealth = lungHealth.coerceIn(0, 100)
        val startTimeMsFinal = startTimeMs ?: -1L

        val nowMs = System.currentTimeMillis()
        val elapsedMs = if (startTimeMsFinal > 0) (nowMs - startTimeMsFinal).coerceAtLeast(0L) else 0L
        val elapsedSeconds = (elapsedMs / 1000).toDouble()

        val durationHeaderText = if (startTimeMsFinal <= 0) {
            context.getString(R.string.widget_no_data)
        } else {
            formatDurationHeader(elapsedMs)
        }

        val totalCigs = (elapsedSeconds * dailyCigarettes / (24 * 3600)).toInt()
        val costPerCig = if (cigarettesPerPack > 0) pricePerPack.toDouble() / cigarettesPerPack else 0.0
        val savedMoney = (totalCigs * costPerCig).toInt()
        val savedMoneyFormatted = String.format(Locale.KOREA, "₩%,d", savedMoney)
        val skippedCigsText = "${totalCigs}개비"
        val lungPercentText = "${lungHealth}%"

        val views = RemoteViews(context.packageName, R.layout.widget_quittime).apply {
            setTextViewText(R.id.widget_duration, durationHeaderText)
            setTextViewText(R.id.widget_saved_money, savedMoneyFormatted)
            setTextViewText(R.id.widget_skipped_cigs, skippedCigsText)
            setTextViewText(R.id.widget_lung_percent, lungPercentText)
            setProgressBar(R.id.widget_lung_progress, 100, lungHealth, false)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_quittime_root, pending)
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun getPrefInt(prefs: android.content.SharedPreferences, key: String, default: Int): Int {
        val longVal = prefs.getLong(key, -1L)
        if (longVal >= 0) return longVal.toInt()
        return prefs.getInt(key, default)
    }

    /** 헤더용 간단 형식: 금연 N일 N시간 */
    private fun formatDurationHeader(millis: Long): String {
        if (millis < 0) return "금연 0일 0시간"
        val totalSeconds = (millis / 1000).toInt()
        val totalDays = totalSeconds / 86400
        val years = totalDays / 365
        val remainderDays = totalDays % 365
        val months = remainderDays / 30
        val days = remainderDays % 30
        val hours = (totalSeconds / 3600) % 24

        val parts = mutableListOf<String>()
        if (years > 0) parts.add("${years}년")
        if (months > 0) parts.add("${months}개월")
        if (days > 0 || parts.size > 0) parts.add("${days}일")
        parts.add("${hours}시간")
        return "금연 " + parts.joinToString(" ")
    }

    companion object {
        private const val WIDGET_PREFS_NAME = "NonsmokingWidgetPrefs"
        private const val KEY_START_TIME = "startTime"
        private const val KEY_DAILY_CIGS = "dailyCigarettes"
        private const val KEY_CIGS_PER_PACK = "cigarettesPerPack"
        private const val KEY_PRICE_PER_PACK = "pricePerPack"
        private const val KEY_LUNG_HEALTH = "lungHealth"

        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_KEY_START_TIME = "flutter.startTime"
        private const val FLUTTER_KEY_DAILY_CIGS = "flutter.dailyCigarettes"
        private const val FLUTTER_KEY_CIGS_PER_PACK = "flutter.cigarettesPerPack"
        private const val FLUTTER_KEY_PRICE_PER_PACK = "flutter.pricePerPack"
        private const val FLUTTER_KEY_LUNG_HEALTH = "flutter.lungHealth"

        /** Flutter에서 호출: 위젯 표시용 데이터를 네이티브에 저장 후 위젯 갱신 */
        fun syncDataFromFlutter(context: Context, args: Map<String, Any>) {
            context.getSharedPreferences(WIDGET_PREFS_NAME, Context.MODE_PRIVATE).edit().apply {
                (args["startTime"] as? Number)?.toLong()?.takeIf { it > 0 }?.let { putLong(KEY_START_TIME, it) }
                (args["dailyCigarettes"] as? Number)?.toInt()?.let { putInt(KEY_DAILY_CIGS, it) }
                (args["cigarettesPerPack"] as? Number)?.toInt()?.let { putInt(KEY_CIGS_PER_PACK, it) }
                (args["pricePerPack"] as? Number)?.toInt()?.let { putInt(KEY_PRICE_PER_PACK, it) }
                (args["lungHealth"] as? Number)?.toInt()?.let { putInt(KEY_LUNG_HEALTH, it.coerceIn(0, 100)) }
                apply()
            }
        }

        fun requestUpdate(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NonsmokingWidget::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, NonsmokingWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}

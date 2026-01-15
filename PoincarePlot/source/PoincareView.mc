import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

class PoincareView extends WatchUi.View {

    // --- 數據存儲 ---
    // 使用明確型別，避免編譯器推斷錯誤
    private var lastRR as Number? = null;
    private var points as Array<Array<Number>> = [] as Array<Array<Number>>; 
    private var maxPoints as Number = 60;
    
    // --- 模式設定 ---
    private var displayMode as Number = 0;
    private var minRR as Number = 500;
    private var maxRR as Number = 1500;

    // --- UI 佈局參數 (初始化預設值避免 onUpdate 早於 onLayout 執行時崩潰) ---
    private var screenW as Number = 390;
    private var screenH as Number = 390;
    private var canvasSize as Number = 300;
    private var offsetX as Number = 45;
    private var offsetY as Number = 45;

    function initialize() {
        try {
            System.println("View: initialize start");
            View.initialize();
            System.println("View: initialize end");
        } catch (e) {
            System.println("Crash in View.initialize: " + e.getErrorMessage());
        }
    }

    function onLayout(dc as Dc) as Void {
        try {
            System.println("View: onLayout start");
            screenW = dc.getWidth();
            screenH = dc.getHeight();
            
            // 確保畫布為正方形且不超出圓形螢幕安全邊界
            canvasSize = (screenW * 0.70).toNumber(); 
            offsetX = (screenW - canvasSize) / 2;
            offsetY = (screenH - canvasSize) / 2;
            System.println("View: onLayout end. CanvasSize=" + canvasSize);
        } catch (e) {
            System.println("Crash in View.onLayout: " + e.getErrorMessage());
        }
    }

    // 公開給 App 類別調用 (Sensor Listener)
    public function onNewRRData(intervals as Array<Number>) as Void {
        try {
            processIntervals(intervals);
            // 請求立即重繪
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("Error in onNewRRData: " + e.getErrorMessage());
        }
    }

    private function processIntervals(intervals as Array<Number>) as Void {
        for (var i = 0; i < intervals.size(); i++) {
            var currentRR = intervals[i];

            if (lastRR != null) {
                // 修改：儲存原始 RR 數值對 [rr1, rr2]，而非像素座標
                // 這樣才能在 AUTO 模式下重新計算不同範圍的座標
                points.add([lastRR as Number, currentRR]);
                
                // 2. 更穩定的移除舊點方式
                if (points.size() > maxPoints) {
                    points = points.slice(1, null) as Array<Array<Number>>;
                }
            }
            lastRR = currentRR;
        }
    }

    private function calculatePixel(rrX as Number, rrY as Number) as Array<Number> {
        // 預防除以零：如果範圍太小，設定一個最小分母
        var range = (maxRR - minRR).toFloat();
        if (range <= 0) { range = 1.0; } 

        var x = (rrX - minRR).toFloat() / range * canvasSize;
        var y = (rrY - minRR).toFloat() / range * canvasSize;
        
        // 限制在畫布範圍內 (Clamping)
        x = clamp(x, 0.0, canvasSize.toFloat());
        y = clamp(y, 0.0, canvasSize.toFloat());

        return [ (x.toNumber() + offsetX), (offsetY + canvasSize - y.toNumber()) ] as Array<Number>;
    }

    private function clamp(val as Float, min as Float, max as Float) as Float {
        if (val < min) { return min; }
        if (val > max) { return max; }
        return val;
    }

    private function updateDynamicRange() as Void {
        // 真實自動縮放：遍歷所有點找出 Min/Max
        if (points.size() == 0) { return; }

        var localMin = 9999;
        var localMax = 0;

        for (var i = 0; i < points.size(); i++) {
            var p = points[i]; // p is [rr1, rr2]
            var v1 = p[0];
            var v2 = p[1];
            
            if (v1 < localMin) { localMin = v1; }
            if (v2 < localMin) { localMin = v2; }
            if (v1 > localMax) { localMax = v1; }
            if (v2 > localMax) { localMax = v2; }
        }

        // 添加邊距 padding：讓數據佔畫面的 80-90%
        // 計算動態 margin：範圍的 10% 或至少 10ms
        var range = localMax - localMin;
        var padding = (range * 0.1).toNumber();
        if (padding < 10) { padding = 10; }

        minRR = localMin - padding;
        maxRR = localMax + padding;

        // 確保至少有 40ms 的範圍，避免因為數值完全相同導致範圍為 0
        if (maxRR - minRR < 40) {
            var center = (minRR + maxRR) / 2;
            minRR = center - 20;
            maxRR = center + 20;
        }
        
        // 絕對邊界保護
        if (minRR < 0) { minRR = 0; }
    }

    function onUpdate(dc as Dc) as Void {
        try {
            // 計算 Auto Scale
            if (displayMode == 2) { // AUTO Mode
                 updateDynamicRange();
            }

            // 背景與畫布
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();

            dc.setPenWidth(1);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(offsetX, offsetY, canvasSize, canvasSize);
            dc.drawLine(offsetX, offsetY + canvasSize, offsetX + canvasSize, offsetY);

            // 繪製模式文字 (顯示對應心率範圍 BPM)
            // RR(ms) 轉 BPM 公式: 60000 / RR
            var lowBpm = 0;
            var highBpm = 0;

            // 確保分母不為零且合理
            if (maxRR > 0) { lowBpm = 60000 / maxRR; }
            if (minRR > 0) { highBpm = 60000 / minRR; }

            var modeName = "";
            if (displayMode == 2) { modeName = "AUTO "; }

            var infoStr = modeName + "[" + lowBpm + "-" + highBpm + " BPM]";
            
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, offsetY - 25, Graphics.FONT_XTINY, infoStr, Graphics.TEXT_JUSTIFY_CENTER);

            // 繪製點 (需要即時計算像素座標)
            var pointsSize = points.size();
            for (var i = 0; i < pointsSize; i++) {
                var rawP = points[i]; // raw [rr1, rr2]
                var p = calculatePixel(rawP[0], rawP[1]); // Convert to pixels
                
                if (i == pointsSize - 1) {
                    dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(p[0], p[1], 4);
                } else {
                    // 區分歷史數據顏色
                    var color = (i < pointsSize / 2) ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(p[0], p[1], 2);
                }
            }
            
            // 心率數值
            var info = Activity.getActivityInfo();
            var hr = (info != null && info.currentHeartRate != null) ? info.currentHeartRate.toString() : "--";
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, offsetY + canvasSize + 5, Graphics.FONT_TINY, "HR: " + hr, Graphics.TEXT_JUSTIFY_CENTER);

            // [DEBUG] 顯示除錯資訊
            var debugStr = "Pts:" + points.size() + " Last:" + (lastRR != null ? lastRR : "null");
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, screenH - 30, Graphics.FONT_XTINY, debugStr, Graphics.TEXT_JUSTIFY_CENTER);
        } catch (e) {
            System.println("Error in onUpdate: " + e.getErrorMessage());
            e.printStackTrace();
            
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_RED);
            dc.clear();
            dc.drawText(dc.getWidth()/2, dc.getHeight()/2, Graphics.FONT_TINY, "Err: " + e.getErrorMessage(), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // 由 App 類別切換模式
    function updateModeFromSettings() as Void {
        try {
            System.println("View: updateModeFromSettings start");
            displayMode = (displayMode + 1) % 3;
            
            if (displayMode == 0) {
                minRR = 500; maxRR = 1500;
            } else if (displayMode == 1) {
                minRR = 700; maxRR = 1300;
            }
            
            // 保留數據，讓 onUpdate 根據新模式重新繪製
            // points = [] as Array<Array<Number>>;
            // lastRR = null;
            System.println("View: updateModeFromSettings end. Mode=" + displayMode);
        } catch (e) {
            System.println("Crash in View.updateModeFromSettings: " + e.getErrorMessage());
        }
    }
}
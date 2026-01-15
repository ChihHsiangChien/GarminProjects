import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Math;
import Toybox.ActivityRecording;
import Toybox.FitContributor;

class PoincareView extends WatchUi.View {

    // --- 數據存儲 (Optimization: Circular Buffer) ---
    private var maxPoints as Number = 60;
    // Init with nulls, but usage is safe due to pointsCount logic
    private var pointsBuffer as Array<Array<Number>?> = new [60]; 
    private var writeIndex as Number = 0;
    private var pointsCount as Number = 0;
    private var lastRR as Number? = null;

    // --- FIT Recording ---
    private var session as ActivityRecording.Session? = null;
    private var sd1Field as FitContributor.Field? = null;
    private var sd2Field as FitContributor.Field? = null;

    // --- 統計快取 ---
    private var cachedSD1 as Float = 0.0;
    private var cachedSD2 as Float = 0.0;
    private var cachedRatio as Float = 0.0;
    private var cachedMeanX as Float = 0.0;
    private var cachedMeanY as Float = 0.0;
    
    // --- 模式設定 ---
    private var displayMode as Number = 0;
    // Default Mode 0 (Wide): 40-120 BPM -> 500ms - 1500ms
    private var minRR as Number = 500;
    private var maxRR as Number = 1500;

    // --- 常數 ---
    private const SQRT2 = 1.41421356;

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
                // Circular Buffer Write
                pointsBuffer[writeIndex] = [lastRR as Number, currentRR];
                
                writeIndex = (writeIndex + 1);
                if (writeIndex >= maxPoints) {
                    writeIndex = 0;
                }
                
                if (pointsCount < maxPoints) {
                    pointsCount++;
                }
            }
            lastRR = currentRR;
        }
        
        // 更新統計數據 (僅在有新數據且點數足夠時計算)
        if (pointsCount >= 2) {
            calculateStats();
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
        // 真實自動縮放：遍歷 Buffer 找出 Min/Max
        if (pointsCount == 0) { return; }

        var localMin = 9999;
        var localMax = 0;

        for (var i = 0; i < pointsCount; i++) {
            var p = pointsBuffer[i] as Array<Number>; // Access all valid points in buffer
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

            // 繪製最後 10 點的連線 (僅在 AUTO 模式)
            if (displayMode == 2 && pointsCount > 1) {
                 var rangeToCheck = 10;
                 if (rangeToCheck > pointsCount) { rangeToCheck = pointsCount; }
                 
                 dc.setPenWidth(1);
                 dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                 
                 // 從最新的點開始回溯
                 // 最新點 index = (writeIndex - 1 + maxPoints) % maxPoints
                 var lastIdx = (writeIndex - 1 + maxPoints) % maxPoints;
                 var prevRaw = pointsBuffer[lastIdx] as Array<Number>;
                 var prevP = calculatePixel(prevRaw[0], prevRaw[1]);
                 
                 for (var i = 1; i < rangeToCheck; i++) {
                     var currIdx = (lastIdx - i + maxPoints) % maxPoints;
                     var currRaw = pointsBuffer[currIdx] as Array<Number>;
                     var currP = calculatePixel(currRaw[0], currRaw[1]);

                     // Meteor Tail Effect: Alpha Fade
                     // Calculate alpha based on position (i). Range i: 1 to rangeToCheck-1
                     // i=1 (oldest in this loop) -> low alpha, i=rangeToCheck-1 (newest) -> high alpha
                     // But wait, the loop is finding 'currIdx' which is moving backwards in time?
                     // No, let's re-read the loop:
                     // lastIdx = newest.
                     // i goes from 1 to rangeToCheck.
                     // currIdx = (lastIdx - i ...). So i=1 is close to newest (lastIdx-1). i=rangeToCheck is oldest.
                     
                     // So small i (recent) -> High Alpha. Large i (old) -> Low Alpha.
                     var alpha = 255 - ((i.toFloat() / rangeToCheck.toFloat()) * 200).toNumber();
                     if (alpha < 50) { alpha = 50; }
                     
                     // Use ARGB for transparency if screen supports it (most do now)
                     // Color: LT_GRAY = 0xAAAAAA.
                     // 0xAA = 170.
                     var colorBase = 0xAAAAAA;
                     var colorWithAlpha = (alpha << 24) | colorBase;
                     
                     dc.setColor(colorWithAlpha, Graphics.COLOR_TRANSPARENT);
                     
                     dc.drawLine(prevP[0], prevP[1], currP[0], currP[1]);
                     
                     prevP = currP;
                 }
            }
            
            // 顯示 SD1, SD2, Ratio 和 橢圓 (僅當點數 >= 30)
            if (pointsCount >= 30) {
                // 1. 顯示數值
                var sd1Str = "SD1: " + cachedSD1.format("%.1f");
                var sd2Str = "SD2: " + cachedSD2.format("%.1f");
                var ratioStr = "R: " + cachedRatio.format("%.1f");
                
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(offsetX + 5, offsetY + 5, Graphics.FONT_XTINY, sd1Str, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(offsetX + 5, offsetY + 22, Graphics.FONT_XTINY, sd2Str, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(offsetX + 5, offsetY + 39, Graphics.FONT_XTINY, ratioStr, Graphics.TEXT_JUSTIFY_LEFT);
                
                // 2. 繪製橢圓
                // 需要將 SD 值轉換為像素長度
                // 1 pixel = range / canvasSize (ms per pixel? No, buffer pixels)
                // correct mult: sd_ms * (canvasSize / range_ms)
                var rangeF = (maxRR - minRR).toFloat();
                if (rangeF <= 0) { rangeF = 1.0; }
                var scale = canvasSize.toFloat() / rangeF;
                
                // 修改：使用 2 倍標準差 (涵蓋 ~95%)，避免橢圓過大
                var sd1Pixels = cachedSD1 * scale * 2; 
                var sd2Pixels = cachedSD2 * scale * 2; 
                
                // 橢圓中心：使用計算出的精確平均值
                var centerP = calculatePixel(cachedMeanX.toNumber(), cachedMeanY.toNumber());
                
                dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                drawRotatedEllipse(dc, centerP[0], centerP[1], sd1Pixels, sd2Pixels);
            }

            // 繪製點 (遍歷 Buffer)
            for (var i = 0; i < pointsCount; i++) {
                // Buffer 是循環的，但這裡為了繪製點，不需要特定的時間順序，直接遍歷即可 (顏色可能需要順序?)
                // 如果需要顏色淡入淡出 (舊->新)，則需要按時間順序遍歷
                
                // 按時間順序獲取索引
                // 最舊的點: (writeIndex - pointsCount + i + maxPoints) % maxPoints ? NO
                // If full: writeIndex is oldest (overwritten next), writeIndex-1 is newest.
                // Correct logic:
                // Oldest index = (writeIndex - pointsCount + maxPoints) % maxPoints
                // i=0 -> Oldest, i=pointsCount-1 -> Newest
                
                var idx = (writeIndex - pointsCount + i + maxPoints) % maxPoints;
                var rawP = pointsBuffer[idx] as Array<Number>;
                var p = calculatePixel(rawP[0], rawP[1]);

                if (i == pointsCount - 1) {
                    // 最新點
                    dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(p[0], p[1], 4);
                } else {
                    // 區分歷史數據顏色
                    var color = (i < pointsCount / 2) ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
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
            var debugStr = " Last:" + (lastRR != null ? lastRR : "null");
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
            
            var minBpm = 0;
            var maxBpm = 0;

            if (displayMode == 0) {
                // Wide Mode: 60 - 120 BPM
                minBpm = 60; 
                maxBpm = 120;
            } else if (displayMode == 1) {
                // Zoom Mode: 50 - 80 BPM
                minBpm = 50; 
                maxBpm = 80;
            }

            if (displayMode == 0 || displayMode == 1) {
                // RR = 60000 / BPM
                // minRR 對應 maxBpm
                minRR = 60000 / maxBpm;
                // maxRR 對應 minBpm
                maxRR = 60000 / minBpm;
            }
            
            System.println("View: updateModeFromSettings end. Mode=" + displayMode);
        } catch (e) {
            System.println("Crash in View.updateModeFromSettings: " + e.getErrorMessage());
        }
    }

    // --- 統計計算輔助函式 ---
    
    // --- 統計與繪圖輔助 ---



    private function calculateStats() as Void {
        // 優化：直接計算平方和 (One-pass, No array allocation)
        // 使用常數 SQRT2 避免重複計算開根號
        
        var sumX = 0.0;
        var sumY = 0.0;
        
        var sumSd1 = 0.0;
        var sumSqSd1 = 0.0;
        
        var sumSd2 = 0.0;
        var sumSqSd2 = 0.0;
        
        for (var i = 0; i < pointsCount; i++) {
            var p = pointsBuffer[i] as Array<Number>;
            var rr_n = p[0].toFloat();
            var rr_n1 = p[1].toFloat();
            
            sumX += rr_n;
            sumY += rr_n1;
            
            // SD1: (RRn - RRn+1) / sqrt(2)
            var val1 = (rr_n - rr_n1) / SQRT2;
            sumSd1 += val1;
            sumSqSd1 += (val1 * val1);
            
            // SD2: (RRn + RRn+1) / sqrt(2)
            var val2 = (rr_n + rr_n1) / SQRT2;
            sumSd2 += val2;
            sumSqSd2 += (val2 * val2);
        }
        
        //計算平均值
        if (pointsCount > 0) {
            cachedMeanX = sumX / pointsCount;
            cachedMeanY = sumY / pointsCount;
            
            // 標準差計算: sqrt(Var)
            // Var = E[X^2] - (E[X])^2
            
            var meanSd1 = sumSd1 / pointsCount;
            var varSd1 = (sumSqSd1 / pointsCount) - (meanSd1 * meanSd1);
            if (varSd1 < 0) { varSd1 = 0.0; } // Floating point safety
            cachedSD1 = Math.sqrt(varSd1).toFloat();
            
            var meanSd2 = sumSd2 / pointsCount;
            var varSd2 = (sumSqSd2 / pointsCount) - (meanSd2 * meanSd2);
             if (varSd2 < 0) { varSd2 = 0.0; }
            cachedSD2 = Math.sqrt(varSd2).toFloat();
            
        } else {
            cachedMeanX = 0.0;
            cachedMeanY = 0.0;
            cachedSD1 = 0.0;
            cachedSD2 = 0.0;
        }

        if (cachedSD2 > 0) {
            cachedRatio = cachedSD1 / cachedSD2;
        } else {
            cachedRatio = 0.0;
        }

        // --- FIT Recording Write ---
        if (session != null && session.isRecording()) {
             // 寫入 FIT 數據
             if (sd1Field != null) { sd1Field.setData(cachedSD1); }
             if (sd2Field != null) { sd2Field.setData(cachedSD2); }
        }
    }
    
    // --- FIT Session Management ---
    
    public function startRecording() as Void {
        try {
             if (session == null || !session.isRecording()) {
                 session = ActivityRecording.createSession({
                     :name => "Poincare Analysis",
                     // Using Activity.SPORT_GENERIC as replacement for deprecated ActivityRecording constant
                     :sport => Activity.SPORT_GENERIC,
                     :subSport => Activity.SUB_SPORT_GENERIC
                 });
                 
                 // 連結 XML 裡的欄位 (ID 必須對應 resources/fitfields.xml)
                 // Field 0: SD1
                 sd1Field = session.createField(
                     "sd1", 
                     0, 
                     FitContributor.DATA_TYPE_FLOAT, 
                     { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms" }
                 );
                 
                 // Field 1: SD2
                 sd2Field = session.createField(
                     "sd2", 
                     1, 
                     FitContributor.DATA_TYPE_FLOAT, 
                     { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms" }
                 );
                 
                 session.start();
                 System.println("View: Recording started");
             }
        } catch (e) {
             System.println("Failed to start recording: " + e.getErrorMessage());
        }
    }
    
    public function stopRecording() as Void {
        if (session != null && session.isRecording()) {
            session.stop();
            session.save();
            session = null;
            sd1Field = null;
            sd2Field = null;
            System.println("View: Recording stopped and saved");
        }
    }
    
    // 繪製旋轉 45 度橢圓的邏輯
    private function drawRotatedEllipse(dc as Dc, centerX as Number, centerY as Number, sd1Pixels as Float, sd2Pixels as Float) as Void {
        var numPoints = 32; 
        var angleStep = 2 * Math.PI / numPoints;
        var prevX = 0; 
        var prevY = 0;
        var rotation = Math.PI / 4; 

        for (var i = 0; i <= numPoints; i++) {
            var theta = i * angleStep;
            
            var x = sd2Pixels * Math.cos(theta);
            var y = sd1Pixels * Math.sin(theta);
            
            var rotX = x * Math.cos(rotation) - y * Math.sin(rotation);
            var rotY = x * Math.sin(rotation) + y * Math.cos(rotation);
            
            var screenX = (centerX + rotX).toNumber();
            var screenY = (centerY - rotY).toNumber(); 
            
            if (i > 0) {
                dc.drawLine(prevX, prevY, screenX, screenY);

            }
            prevX = screenX;
            prevY = screenY;
        }
    }
    

}
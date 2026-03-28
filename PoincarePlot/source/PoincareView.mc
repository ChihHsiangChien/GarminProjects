import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Math;
import Toybox.ActivityRecording;
import Toybox.FitContributor;

class PoincareView extends WatchUi.View {

    // --- 數據存儲 (Optimization: Circular Buffer & Coordinate Caching) ---
    // pointsBuffer element: [pixelX, pixelY, timestamp, rawRR_n, rawRR_n1]
    private var maxPoints as Number = 60;
    private var pointsBuffer as Array<Array<Numeric>?> = new [60]; 
    private var writeIndex as Number = 0;
    private var pointsCount as Number = 0;
    private var lastRR as Number? = null;
    private var lastSignalTime as Number = 0;

    // --- FIT Recording ---
    private var session as ActivityRecording.Session? = null;
    private var sd1Field as FitContributor.Field? = null;
    private var sd2Field as FitContributor.Field? = null;
    
    // --- ASM History (Circular) ---
    private var maxAsmHistory as Number = 30;
    private var asmHistorySD1 as Array<Float?> = new [30];
    private var asmHistorySD2 as Array<Float?> = new [30];
    private var asmWriteIdx as Number = 0;
    private var asmHistoryCount as Number = 0;

    // --- Energy Balance History (Circular) ---
    private var maxEbHistory as Number = 300;
    private var ebHistoryRatio as Array<Float?> = new [300];
    private var ebHistoryArea as Array<Float?> = new [300];
    private var ebWriteIdx as Number = 0;
    private var ebHistoryCount as Number = 0;

    // --- 統計快取 ---
    private var cachedSD1 as Float = 0.0;
    private var cachedSD2 as Float = 0.0;
    private var shortSD1 as Float = 0.0;
    private var shortSD2 as Float = 0.0;
    private var cachedRatio as Float = 0.0;
    private var cachedMeanX as Float = 0.0;
    private var cachedMeanY as Float = 0.0;
    
    // --- 顯示設定 ---
    private var displayMode as Number = 0; // 0: Wide, 1: Zoom, 2: Auto, 3: ASM, 4: EB
    private var minRR as Number = 500;
    private var maxRR as Number = 1500;

    // --- 常數 ---
    private const SQRT2 = 1.41421356;
    private const DISCONNECT_THRESHOLD_MS = 3000;

    // --- UI 佈局參數 ---
    private var screenW as Number = 390;
    private var screenH as Number = 390;
    private var canvasSize as Number = 300;
    private var offsetX as Number = 45;
    private var offsetY as Number = 45;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        screenW = dc.getWidth();
        screenH = dc.getHeight();
        canvasSize = (screenW * 0.70).toNumber(); 
        offsetX = (screenW - canvasSize) / 2;
        offsetY = (screenH - canvasSize) / 2;
        refreshAllCoordinates();
    }

    // 公開給 App 類別調用 (Sensor Listener)
    public function onNewRRData(intervals as Array<Number>) as Void {
        try {
            processIntervals(intervals);
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("Error in onNewRRData: " + e.getErrorMessage());
        }
    }

    private function processIntervals(intervals as Array<Number>) as Void {
        var now = System.getTimer();
        if (intervals.size() > 0) {
            lastSignalTime = now;
        }
        
        for (var i = 0; i < intervals.size(); i++) {
            var currentRR = intervals[i];

            if (lastRR != null) {
                // 座標計算 (Pre-calculation)
                var pixels = calculatePixel(lastRR as Number, currentRR);
                
                // pointsBuffer 元素: [pixelX, pixelY, timestamp, rawRR_n, rawRR_n1]
                pointsBuffer[writeIndex] = [
                    pixels[0], 
                    pixels[1], 
                    now, 
                    lastRR as Number, 
                    currentRR
                ];
                
                writeIndex = (writeIndex + 1) % maxPoints;
                if (pointsCount < maxPoints) {
                    pointsCount++;
                }
            }
            lastRR = currentRR;
        }
        
        if (pointsCount >= 2) {
            calculateStats();
        }
    }

    // 核心優化：座標預算
    private function calculatePixel(rrX as Number, rrY as Number) as Array<Number> {
        var range = (maxRR - minRR).toFloat();
        if (range <= 0) { range = 1.0; } 

        var x = (rrX - minRR).toFloat() / range * canvasSize;
        var y = (rrY - minRR).toFloat() / range * canvasSize;
        
        // Clamping
        if (x < 0) { x = 0.0; } else if (x > canvasSize) { x = canvasSize.toFloat(); }
        if (y < 0) { y = 0.0; } else if (y > canvasSize) { y = canvasSize.toFloat(); }

        return [ (x.toNumber() + offsetX), (offsetY + canvasSize - y.toNumber()) ] as Array<Number>;
    }

    // 批次更新所有快取的座標
    private function refreshAllCoordinates() as Void {
        if (pointsCount == 0) { return; }
        for (var i = 0; i < pointsCount; i++) {
            var p = pointsBuffer[i] as Array<Numeric>;
            var pixels = calculatePixel(p[3] as Number, p[4] as Number);
            p[0] = pixels[0];
            p[1] = pixels[1];
        }
    }

    private function updateDynamicRange() as Void {
        if (pointsCount == 0) { return; }

        var localMin = 9999;
        var localMax = 0;

        for (var i = 0; i < pointsCount; i++) {
            var p = pointsBuffer[i] as Array<Numeric>;
            var v1 = p[3] as Number;
            var v2 = p[4] as Number;
            if (v1 < localMin) { localMin = v1; }
            if (v2 < localMin) { localMin = v2; }
            if (v1 > localMax) { localMax = v1; }
            if (v2 > localMax) { localMax = v2; }
        }

        var range = localMax - localMin;
        var padding = (range * 0.1).toNumber();
        if (padding < 10) { padding = 10; }

        var newMin = localMin - padding;
        var newMax = localMax + padding;
        if (newMin < 0) { newMin = 0; }
        if (newMax - newMin < 40) {
            var center = (newMin + newMax) / 2;
            newMin = center - 20;
            newMax = center + 20;
        }

        if (newMin != minRR || newMax != maxRR) {
            minRR = newMin;
            maxRR = newMax;
            refreshAllCoordinates();
        }
    }

    function onUpdate(dc as Dc) as Void {
        try {
            if (displayMode == 2) { // AUTO Mode
                 updateDynamicRange();
            }
            
            if (displayMode == 3) {
                 drawASM(dc);
                 return;
            }
            if (displayMode == 4) {
                 drawEnergyBalance(dc);
                 return;
            }

            // 背景與畫布
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();

            dc.setPenWidth(1);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(offsetX, offsetY, canvasSize, canvasSize);
            dc.drawLine(offsetX, offsetY + canvasSize, offsetX + canvasSize, offsetY);

            // 模式資訊
            var lowBpm = (maxRR > 0) ? 60000 / maxRR : 0;
            var highBpm = (minRR > 0) ? 60000 / minRR : 0;
            var modeName = (displayMode == 2) ? "AUTO " : "";
            var infoStr = modeName + "[" + lowBpm + "-" + highBpm + " BPM]";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, offsetY - 25, Graphics.FONT_XTINY, infoStr, Graphics.TEXT_JUSTIFY_CENTER);

            // 繪製連線 (Meteor Tail - 限流 5 點 & 斷訊檢測)
            if (pointsCount > 1) {
                 var rangeToCheck = 5;
                 if (rangeToCheck > pointsCount) { rangeToCheck = pointsCount; }
                 
                 dc.setPenWidth(2);
                 var lastIdx = (writeIndex - 1 + maxPoints) % maxPoints;
                 var p1 = pointsBuffer[lastIdx] as Array<Numeric>;
                 
                 for (var i = 1; i < rangeToCheck; i++) {
                     var currIdx = (lastIdx - i + maxPoints) % maxPoints;
                     var p2 = pointsBuffer[currIdx] as Array<Numeric>;

                     // 斷訊偵測：檢查兩點間的時間差
                     var timeDiff = (p1[2] as Number) - (p2[2] as Number);
                     if (timeDiff > DISCONNECT_THRESHOLD_MS || timeDiff < 0) {
                         break; // 斷開連線，停止繪製尾跡
                     }

                     var alpha = 255 - (i * 40);
                     if (alpha < 50) { alpha = 50; }
                     dc.setColor((alpha << 24) | 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                     dc.drawLine(p1[0] as Number, p1[1] as Number, p2[0] as Number, p2[1] as Number);
                     p1 = p2;
                 }
            }
            
            // 繪製橢圓與統計
            if (pointsCount >= 30) {
                drawStatsAndEllipse(dc);
            }

            // 繪製點
            for (var i = 0; i < pointsCount; i++) {
                var idx = (writeIndex - pointsCount + i + maxPoints) % maxPoints;
                var p = pointsBuffer[idx] as Array<Numeric>;
                if (i == pointsCount - 1) {
                    dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(p[0] as Number, p[1] as Number, 4);
                } else {
                    var color = (i < pointsCount / 2) ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
                    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                    dc.fillCircle(p[0] as Number, p[1] as Number, 2);
                }
            }
            
            // HR 與信號狀態
            var info = Activity.getActivityInfo();
            var hr = (info != null && info.currentHeartRate != null) ? info.currentHeartRate.toString() : "--";
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenW/2, offsetY + canvasSize + 5, Graphics.FONT_TINY, "HR: " + hr, Graphics.TEXT_JUSTIFY_CENTER);
            drawSignalIndicator(dc, screenW/3, offsetY + canvasSize + 25);

        } catch (e) {
            System.println("Error in onUpdate: " + e.getErrorMessage());
        }
    }

    private function drawStatsAndEllipse(dc as Dc) as Void {
        var sd1Str = "SD1: " + cachedSD1.format("%.1f");
        var sd2Str = "SD2: " + cachedSD2.format("%.1f");
        var ratioStr = "R: " + cachedRatio.format("%.1f");
        var area = 3.1415926 * cachedSD1 * cachedSD2;
        var areaStr = "A: " + area.format("%.0f");
        
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(offsetX + 5, offsetY + 5, Graphics.FONT_XTINY, sd1Str, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(offsetX + 5, offsetY + 22, Graphics.FONT_XTINY, sd2Str, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(offsetX + 5, offsetY + 39, Graphics.FONT_XTINY, ratioStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(offsetX + 5, offsetY + 56, Graphics.FONT_XTINY, areaStr, Graphics.TEXT_JUSTIFY_LEFT);
        
        var rangeF = (maxRR - minRR).toFloat();
        if (rangeF <= 0) { rangeF = 1.0; }
        var scale = canvasSize.toFloat() / rangeF;
        var sd1Pixels = cachedSD1 * scale * 2; 
        var sd2Pixels = cachedSD2 * scale * 2; 
        var centerP = calculatePixel(cachedMeanX.toNumber(), cachedMeanY.toNumber());
        
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        drawRotatedEllipse(dc, centerP[0], centerP[1], sd1Pixels, sd2Pixels);
    }

    private function drawSignalIndicator(dc as Dc, centerX as Number, centerY as Number) as Void {
        var timeSinceLast = System.getTimer() - lastSignalTime;
        var color = Graphics.COLOR_RED;
        if (timeSinceLast < 3000) { color = Graphics.COLOR_GREEN; }
        else if (timeSinceLast < 10000) { color = Graphics.COLOR_YELLOW; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(centerX, centerY, 6);
    }

    private function computeSD(count as Number) as Array<Float> {
        if (pointsCount < 2) { return [0.0, 0.0, 0.0, 0.0]; }
        var effectiveCount = (pointsCount < count) ? pointsCount : count;
        var sumX = 0.0; var sumY = 0.0;
        var sumSd1 = 0.0; var sumSqSd1 = 0.0;
        var sumSd2 = 0.0; var sumSqSd2 = 0.0;
        
        for (var i = 0; i < effectiveCount; i++) {
             var idx = (writeIndex - 1 - i + maxPoints) % maxPoints;
             var p = pointsBuffer[idx] as Array<Numeric>;
             var rr_n = (p[3] as Number).toFloat();
             var rr_n1 = (p[4] as Number).toFloat();
             sumX += rr_n; sumY += rr_n1;
             var v1 = (rr_n - rr_n1) / SQRT2;
             sumSd1 += v1; sumSqSd1 += (v1 * v1);
             var v2 = (rr_n + rr_n1) / SQRT2;
             sumSd2 += v2; sumSqSd2 += (v2 * v2);
        }
        
        var mX = sumX / effectiveCount; var mY = sumY / effectiveCount;
        var mSd1 = sumSd1 / effectiveCount;
        var vSd1 = (sumSqSd1 / effectiveCount) - (mSd1 * mSd1);
        var mSd2 = sumSd2 / effectiveCount;
        var vSd2 = (sumSqSd2 / effectiveCount) - (mSd2 * mSd2);
        
        if (vSd1 < 0) { vSd1 = 0.0; }
        if (vSd2 < 0) { vSd2 = 0.0; }
        
        return [Math.sqrt(vSd1).toFloat(), Math.sqrt(vSd2).toFloat(), mX, mY];
    }

    private function calculateStats() as Void {
        var longStats = computeSD(60);
        cachedSD1 = longStats[0]; cachedSD2 = longStats[1];
        cachedMeanX = longStats[2]; cachedMeanY = longStats[3];
        cachedRatio = (cachedSD2 > 0) ? (cachedSD1 / cachedSD2) : 0.0;

        if (pointsCount >= 15) {
            var shortStats = computeSD(15);
            shortSD1 = shortStats[0]; shortSD2 = shortStats[1];
        } else {
            shortSD1 = cachedSD1; shortSD2 = cachedSD2;
        }

        asmHistorySD1[asmWriteIdx] = shortSD1;
        asmHistorySD2[asmWriteIdx] = shortSD2;
        asmWriteIdx = (asmWriteIdx + 1) % maxAsmHistory;
        if (asmHistoryCount < maxAsmHistory) { asmHistoryCount++; }

        var area = 3.1415926 * cachedSD1 * cachedSD2;
        ebHistoryRatio[ebWriteIdx] = cachedRatio;
        ebHistoryArea[ebWriteIdx] = area.toFloat();
        ebWriteIdx = (ebWriteIdx + 1) % maxEbHistory;
        if (ebHistoryCount < maxEbHistory) { ebHistoryCount++; }

        if (session != null && session.isRecording()) {
             if (sd1Field != null) { sd1Field.setData(cachedSD1); }
             if (sd2Field != null) { sd2Field.setData(cachedSD2); }
        }
    }

    private function drawASM(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        
        // 標題
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW/2, offsetY - 25, Graphics.FONT_XTINY, "Autonomic State Map", Graphics.TEXT_JUSTIFY_CENTER);

        var maxX = 100.0; var maxY = 150.0;
        var gSize = (screenW * 0.65).toNumber();
        var gL = (screenW - gSize) / 2; var gT = (screenH - gSize) / 2;
        var gB = gT + gSize;
        
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(gL, gT, gSize, gSize);
        dc.drawLine(gL, gB, gL + gSize, (gB - (100.0/maxY * gSize)).toNumber());

        // 繪製座標軸標籤
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW/2, gB + 5, Graphics.FONT_XTINY, "SD1", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(gL - 5, screenH/2, Graphics.FONT_XTINY, "SD2", Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (asmHistoryCount > 1) {
            var lastIdx = (asmWriteIdx - 1 + maxAsmHistory) % maxAsmHistory;
            var px = gL + (asmHistorySD1[lastIdx] / maxX * gSize);
            var py = gB - (asmHistorySD2[lastIdx] / maxY * gSize);
            for (var i = 1; i < asmHistoryCount; i++) {
                var cIdx = (lastIdx - i + maxAsmHistory) % maxAsmHistory;
                var cx = gL + (asmHistorySD1[cIdx] / maxX * gSize);
                var cy = gB - (asmHistorySD2[cIdx] / maxY * gSize);
                var alpha = 255 - (i * 8); if (alpha < 50) { alpha = 50; }
                dc.setColor((alpha << 24) | 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px, py, cx, cy);
                px = cx; py = cy;
            }
        }
        
        if (asmHistoryCount > 0) {
             dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
             dc.fillCircle(gL + (cachedSD1 / maxX * gSize), gB - (cachedSD2 / maxY * gSize), 5);
             dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
             dc.fillCircle(gL + (shortSD1 / maxX * gSize), gB - (shortSD2 / maxY * gSize), 4);
        }
        drawSignalIndicator(dc, screenW/3, offsetY + canvasSize + 25);
    }

    private function drawEnergyBalance(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        
        // 標題
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW/2, offsetY - 25, Graphics.FONT_XTINY, "Energy vs Balance", Graphics.TEXT_JUSTIFY_CENTER);

        var gSize = (screenW * 0.70).toNumber();
        var gL = (screenW - gSize) / 2; var gT = (screenH - gSize) / 2; var gB = gT + gSize;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(gL, gT, gSize, gSize);
        
        // 繪製座標軸標籤與格線
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenW/2, gB + 5, Graphics.FONT_XTINY, "SD1/SD2", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(gL + 5, gT + 5, Graphics.FONT_XTINY, "Area", Graphics.TEXT_JUSTIFY_LEFT);

        // 繪製格線 (X: 0.5, 1.0; Y: 10^3, 10^4)
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        
        // X Grid: 0.5, 1.0 (Range 0.0 - 1.2)
        var x05 = gL + (0.5 / 1.2 * gSize);
        var x10 = gL + (1.0 / 1.2 * gSize);
        dc.drawLine(x05, gT, x05, gB);
        dc.drawLine(x10, gT, x10, gB);
        
        // Y Grid (Log10): 10^3, 10^4 (Range 10^2 - 10^5, i.e., Log 2.0 - 5.0)
        var yLog3 = gB - ((3.0 - 2.0) / (5.0 - 2.0) * gSize);
        var yLog4 = gB - ((4.0 - 2.0) / (5.0 - 2.0) * gSize);
        dc.drawLine(gL, yLog3.toNumber(), gL + gSize, yLog3.toNumber());
        dc.drawLine(gL, yLog4.toNumber(), gL + gSize, yLog4.toNumber());
        
        var minLog = 2.0; var maxLog = 5.0;
        if (ebHistoryCount > 0) {
             var lastIdx = (ebWriteIdx - 1 + maxEbHistory) % maxEbHistory;
             var nowArea = ebHistoryArea[lastIdx]; 
             if (nowArea == null || nowArea < 1.0) { nowArea = 1.0; } // 對數定義域保護
             var nowRatio = ebHistoryRatio[lastIdx];
             if (nowRatio == null) { nowRatio = 0.0; }

             var px = gL + ( (nowRatio > 1.2 ? 1.2 : nowRatio) / 1.2 * gSize);
             var areaLog = Math.ln(nowArea) / Math.ln(10);
             if (areaLog < 2.0) { areaLog = 2.0; } else if (areaLog > 5.0) { areaLog = 5.0; }
             var py = gB - ((areaLog - minLog) / (maxLog - minLog) * gSize);
             
             if (ebHistoryCount > 1) {
                 var prevX = px; var prevY = py;
                 for (var i = 1; i < ebHistoryCount; i++) {
                     var cIdx = (lastIdx - i + maxEbHistory) % maxEbHistory;
                     var cArea = ebHistoryArea[cIdx]; 
                     if (cArea == null || cArea < 1.0) { cArea = 1.0; }
                     var cRatio = ebHistoryRatio[cIdx];
                     if (cRatio == null) { cRatio = 0.0; }

                     var cx = gL + ( (cRatio > 1.2 ? 1.2 : cRatio) / 1.2 * gSize);
                     var cLog = Math.ln(cArea) / Math.ln(10);
                     if (cLog < 2.0) { cLog = 2.0; } else if (cLog > 5.0) { cLog = 5.0; }
                     var cy = gB - ((cLog - minLog) / (maxLog - minLog) * gSize);
                     var alpha = 200 - (i * 0.6); if (alpha < 20) { alpha = 20; }
                     dc.setColor((alpha.toNumber() << 24) | 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                     dc.drawLine(prevX, prevY, cx, cy);
                     prevX = cx; prevY = cy;
                 }
             }
             dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
             dc.fillCircle(px, py, 6);
        }
        drawSignalIndicator(dc, screenW/3, offsetY + canvasSize + 25);
    }

    function updateModeFromSettings() as Void {
        displayMode = (displayMode + 1) % 5;
        if (displayMode == 0) { minRR = 60000 / 130; maxRR = 60000 / 50; }
        else if (displayMode == 1) { minRR = 60000 / 90; maxRR = 60000 / 60; }
        refreshAllCoordinates();
    }

    public function startRecording() as Void {
        if (session == null || !session.isRecording()) {
            session = ActivityRecording.createSession({:name => "Poincare Analysis", :sport => Activity.SPORT_GENERIC, :subSport => Activity.SUB_SPORT_GENERIC});
            sd1Field = session.createField("sd1", 0, FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms"});
            sd2Field = session.createField("sd2", 1, FitContributor.DATA_TYPE_FLOAT, {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms"});
            session.start();
        }
    }

    public function stopRecording() as Void {
        if (session != null && session.isRecording()) {
            session.stop(); session.save(); session = null;
        }
    }
    
    private function drawRotatedEllipse(dc as Dc, centerX as Number, centerY as Number, sd1Pixels as Float, sd2Pixels as Float) as Void {
        var numPoints = 32; var angleStep = 2 * Math.PI / numPoints;
        var prevX = 0; var prevY = 0; var rotation = Math.PI / 4; 
        for (var i = 0; i <= numPoints; i++) {
            var theta = i * angleStep;
            var x = sd2Pixels * Math.cos(theta); var y = sd1Pixels * Math.sin(theta);
            var rotX = x * Math.cos(rotation) - y * Math.sin(rotation);
            var rotY = x * Math.sin(rotation) + y * Math.cos(rotation);
            var screenX = (centerX + rotX).toNumber(); var screenY = (centerY - rotY).toNumber(); 
            if (i > 0) { dc.drawLine(prevX, prevY, screenX, screenY); }
            prevX = screenX; prevY = screenY;
        }
    }
}
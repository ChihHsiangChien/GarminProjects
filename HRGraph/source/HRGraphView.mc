import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;

class HRGraphView extends WatchUi.DataField {
    // 儲存心率數據的陣列 (BPM)
    private var hrHistory as Array<Number> = [];
    private var maxPoints = 60; 
    private var lastHR = 0;

    function initialize() {
        DataField.initialize();
    }

    // 每秒執行一次，獲取當前心率
    function compute(info as Activity.Info) as Void {
        if (info != null && info.currentHeartRate != null) {
            lastHR = info.currentHeartRate;
            hrHistory.add(lastHR);
            
            // 使用 if 替代 while，防止潛在的無限迴圈
            // 每次 compute 只會增加一個點，所以 if 就足以維持長度
            if (hrHistory.size() > maxPoints) {
                hrHistory.remove(0);
            }

            // Data Field 不需要手動呼叫 requestUpdate()，系統每秒會自動重繪
        }
    }
    function onUpdate(dc as Dc) as Void {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        // 左右留白 30 像素（或 25，取較大值）
        var sideMargin = (screenWidth >= 60) ? 30 : 25;
        var rectWidth = screenWidth - sideMargin * 2;
        var offsetX = sideMargin;
        // 高度 30%~70%（共 40% 高度）
        var rectHeight = screenHeight * 0.4;
        var offsetY = screenHeight * 0.3;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var size = hrHistory.size();
        if (size < 2) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(screenWidth/2, screenHeight/2, Graphics.FONT_SMALL, "Collecting data...", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // 1. 只用即將被繪製的最後 points 個點自動縮放
        var minHR = 255;
        var maxHR = 0;
        var points = (size < maxPoints) ? size : maxPoints;
        var start = size - points;
        for (var i = start; i < size; i++) {
            if (hrHistory[i] > maxHR) { maxHR = hrHistory[i]; }
            if (hrHistory[i] < minHR) { minHR = hrHistory[i]; }
        }
        // 記錄原始 min/max 供顯示用
        var origMinHR = minHR;
        var origMaxHR = maxHR;
        // 強制區間至少為 10，避免圖形過於平緩
        if ((maxHR - minHR) < 10) {
            var mid = (maxHR + minHR) / 2.0;
            minHR = mid - 5;
            maxHR = mid + 5;
        }

        // 2. 繪圖設定
        dc.setAntiAlias(true);
        // 心跳線條顏色：高於150紅色，否則綠色
        var lineColor = (lastHR > 150) ? Graphics.COLOR_RED : Graphics.COLOR_GREEN;
        dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);

        // 以圖表區為基準
        var xStep = rectWidth.toFloat() / (maxPoints - 1);
        // X 起點：未滿 maxPoints 時靠右對齊
        var xStart = offsetX + rectWidth - xStep * (points - 1);
        var topPadding = rectHeight * 0.10;    // 上方 10%
        var bottomPadding = rectHeight * 0.10; // 下方 10%
        var chartHeight = rectHeight - (topPadding + bottomPadding);

        // 畫外框細線（用 drawLine 畫四邊）
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        // 上邊
        dc.drawLine(offsetX, offsetY, offsetX + rectWidth, offsetY);
        // 下邊
        dc.drawLine(offsetX, offsetY + rectHeight, offsetX + rectWidth, offsetY + rectHeight);
        // 左邊
        dc.drawLine(offsetX, offsetY, offsetX, offsetY + rectHeight);
        // 右邊
        dc.drawLine(offsetX + rectWidth, offsetY, offsetX + rectWidth, offsetY + rectHeight);

        // 3. 從右邊往回計算座標，只繪製最後 points 個點
        // 畫折線圖（心跳線條）
        dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        for (var i = start; i < size - 1; i++) {
            var idx = i - start; // 0..points-2
            var x1 = xStart + (idx * xStep);
            var x2 = xStart + ((idx + 1) * xStep);

            var y1 = offsetY + rectHeight - (bottomPadding + ((hrHistory[i] - minHR).toFloat() / (maxHR - minHR) * chartHeight));
            var y2 = offsetY + rectHeight - (bottomPadding + ((hrHistory[i+1] - minHR).toFloat() / (maxHR - minHR) * chartHeight));

            dc.drawLine(x1, y1, x2, y2);

            if (i == size - 2) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x2, y2, 4);
            }
        }

        // 4. 文字顯示
        // HR 數字垂直置中於圖表區上方的空間
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var hrTextY = offsetY / 2; // offsetY 是圖表區上緣，0~offsetY 的中間
        dc.drawText(screenWidth/2, hrTextY, Graphics.FONT_MEDIUM, lastHR.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        // 圖表下方顯示原始 minHR/maxHR
        var minText = "min: " + origMinHR.toString();
        var maxText = "max: " + origMaxHR.toString();
        var labelY_min = offsetY + rectHeight + (screenHeight * 0.02); // 外框下方一點點
        var labelY_max = labelY_min + (screenHeight * 0.08); // 再往下排一行
        // 顯示 minHR
        dc.drawText(screenWidth/2, labelY_min, Graphics.FONT_SMALL, minText, Graphics.TEXT_JUSTIFY_CENTER);
        // 顯示 maxHR
        dc.drawText(screenWidth/2, labelY_max, Graphics.FONT_SMALL, maxText, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
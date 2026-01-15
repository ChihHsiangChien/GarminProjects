import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Sensor;


class PoincareApp extends Application.AppBase {

    public var view as PoincareView?;

    function initialize() {
        System.println("App: initialize start");
        AppBase.initialize();
        System.println("App: initialize end");
    }

    function onStart(state as Dictionary?) as Void {
        System.println("App: onStart");
        
        // 註冊感測器監聽器
        var options = {
            :period => 1, // 採樣週期，單位為秒
            :heartBeatIntervals => {
                :enabled => true // 顯式啟用心跳間隔數據
            }
        };

        try {
            Sensor.registerSensorDataListener(method(:onSensorData), options);
            System.println("App: Sensor listener registered successfully");
        } catch(e) {
            System.println("App: Failed to register sensor listener: " + e.getErrorMessage());
        }
    }

    function onStop(state as Dictionary?) as Void {
        System.println("App: onStop");
        if (Sensor has :unregisterSensorDataListener) {
            Sensor.unregisterSensorDataListener();
        }
        
        // Stop FIT recording
        if (view != null) {
            view.stopRecording();
        }
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        if (sensorData has :heartRateData && sensorData.heartRateData != null) {
            var hrData = sensorData.heartRateData;
            
            // 檢查心跳間隔數據是否存在
            if (hrData has :heartBeatIntervals && hrData.heartBeatIntervals != null) {
                var intervals = hrData.heartBeatIntervals;
                // intervals 是一個整數陣列 (Array of Numbers)，單位為毫秒 (ms)
                if (intervals != null && view != null) {
                    view.onNewRRData(intervals);
                }
            }
        }
    }



    //! Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        try {
            System.println("App: getInitialView start");
            view = new PoincareView();
            var delegate = new PoincareDelegate(view);
            // Initialize with current settings
            view.updateModeFromSettings();
            
            // Start FIT recording automatically
            view.startRecording();
            
            System.println("App: getInitialView returning");
            return [ view, delegate ];
        } catch (e) {
            System.println("Crash in App.getInitialView: " + e.getErrorMessage());
            throw e; 
        }
    }
    
    // ... existing onSettingsChanged ...
    function onSettingsChanged() {
        if (view != null) {
             view.updateModeFromSettings();
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as PoincareApp {
    return Application.getApp() as PoincareApp;
}

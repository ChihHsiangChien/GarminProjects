import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// 將類別名稱改為 HRGraphApp
class HRGraphApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() 在應用程式啟動時呼叫
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() 在應用程式結束時呼叫
    function onStop(state as Dictionary?) as Void {
    }

    // 回傳初始視圖，這裡改為呼叫新的 HRGraphView 類別
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new HRGraphView() ];
    }

}

// 全域函式也同步修改名稱與回傳型別
function getApp() as HRGraphApp {
    return Application.getApp() as HRGraphApp;
}
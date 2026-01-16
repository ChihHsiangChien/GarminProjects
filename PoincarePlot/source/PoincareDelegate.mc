import Toybox.Lang;
import Toybox.WatchUi;

class PoincareDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PoincareView;

    function initialize(view as PoincareView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onBack() {
        // Exit the app
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onSelect() {
        // Toggle mode on select/enter button
        _view.updateModeFromSettings(); // Reusing the mode toggle logic
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        // Up button
        return true;
    }

    function onNextPage() {
        // Down button
        return true;
    }
}

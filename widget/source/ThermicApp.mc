import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Widget that controls Therm-ic heated gear from the wrist.
class ThermicApp extends Application.AppBase {

    private var _model as Model? = null;
    private var _transport as Transport? = null;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        System.println("app: start");
        var model = new $.Model();
        var transport = $.makeTransport(model);
        _model = model;
        _transport = transport;
        transport.start();
    }

    public function onStop(state as Dictionary?) as Void {
        System.println("app: stop");
        if (_transport != null) {
            (_transport as Transport).stop();
        }
        _transport = null;
        _model = null;
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var model = _model as Model;
        return [new $.MainView(model), new $.MainDelegate(model, _transport as Transport)];
    }
}

import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Widget that controls Therm-ic heated gear from the wrist.
class ThermicApp extends Application.AppBase {

    private var _model as Model? = null;
    private var _transport as Transport? = null;
    // The transport has no clock of its own; this one drives its housekeeping.
    private var _timer as Timer.Timer? = null;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        System.println("app: start");
        var model = new $.Model();
        // The widget also shows remaining heat time, the temperature inside the pack
        // and the target temperature.
        model.details = true;
        var transport = $.makeTransport(model);
        _model = model;
        _transport = transport;
        transport.start();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1000, true);
        _timer = timer;
    }

    public function onStop(state as Dictionary?) as Void {
        System.println("app: stop");
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
        if (_transport != null) {
            (_transport as Transport).stop();
        }
        _transport = null;
        _model = null;
    }

    public function onTick() as Void {
        if (_transport != null) {
            (_transport as Transport).onTick();
        }
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var model = _model as Model;
        return [new $.MainView(model), new $.MainDelegate(model, _transport as Transport)];
    }
}

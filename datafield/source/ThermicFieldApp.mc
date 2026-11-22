import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Data field that shows the heat level during an activity and records it.
//
// It only listens. A data field gets no button input on this watch, so nothing here
// calls Transport.setLevel().
class ThermicFieldApp extends Application.AppBase {

    private var _model as Model? = null;
    private var _transport as Transport? = null;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        note("app start");
        var model = new $.Model();
        var transport = $.makeTransport(model);
        _model = model;
        _transport = transport;
        transport.start();
    }

    // The watch calls this twice when the activity ends.
    public function onStop(state as Dictionary?) as Void {
        note("app stop");
        if (_transport != null) {
            (_transport as Transport).stop();
        }
        _transport = null;
        _model = null;
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        note("view created");
        return [new $.HeatField(_model as Model, _transport as Ticker)];
    }

    private function note(text as String) as Void {
        System.println("field " + (System.getTimer() / 1000) + " " + text);
    }
}

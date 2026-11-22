import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The menu behind MENU on the level page.
class MoreDelegate extends WatchUi.Menu2InputDelegate {

    private var _model as Model;
    private var _transport as Transport;

    public function initialize(model as Model, transport as Transport) {
        Menu2InputDelegate.initialize();
        _model = model;
        _transport = transport;
    }

    public function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :temperature) {
            System.println("menu: temperature page");
            var state = new $.TargetState(_model);
            WatchUi.pushView(new $.TemperatureView(_model, state),
                new $.TemperatureDelegate(_transport, state), WatchUi.SLIDE_LEFT);
        } else if (id == :diagnostics) {
            System.println("menu: diagnostics page");
            _transport.readDiagnostics();
            WatchUi.pushView(new $.DiagnosticsView(_model),
                new $.DiagnosticsDelegate(_transport), WatchUi.SLIDE_LEFT);
        }
    }
}

// Diagnostics page: values a pack gives that are of little use day to day. They are
// read when the page opens and again on START.
class DiagnosticsView extends WatchUi.View {

    private var _model as Model;

    public function initialize(model as Model) {
        View.initialize();
        _model = model;
    }

    public function onUpdate(dc as Dc) as Void {
        Screen.drawDiagnostics(dc, _model);
    }
}

class DiagnosticsDelegate extends WatchUi.BehaviorDelegate {

    private var _transport as Transport;

    public function initialize(transport as Transport) {
        BehaviorDelegate.initialize();
        _transport = transport;
    }

    // START: read the values again. Nothing is written.
    public function onSelect() as Boolean {
        System.println("diagnostics: reading again");
        _transport.readDiagnostics();
        return true;
    }
}

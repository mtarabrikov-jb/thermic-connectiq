import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Main page, shown in the widget loop: level and battery, read-only.
class MainView extends WatchUi.View {

    private var _model as Model;

    public function initialize(model as Model) {
        View.initialize();
        _model = model;
    }

    public function onUpdate(dc as Dc) as Void {
        Screen.draw(dc, _model, false);
    }
}

class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _model as Model;
    private var _transport as Transport;

    public function initialize(model as Model, transport as Transport) {
        BehaviorDelegate.initialize();
        _model = model;
        _transport = transport;
    }

    // START opens the control page. UP and DOWN are deliberately not handled here:
    // on this page they belong to the widget loop, and nothing on it may change the heat.
    public function onSelect() as Boolean {
        System.println("main: select, opening control page");
        // Start from what the packs report right now.
        _model.packReported();
        WatchUi.pushView(new $.ControlView(_model), new $.ControlDelegate(_model, _transport), WatchUi.SLIDE_LEFT);
        return true;
    }
}

// Control page: the only place where the level can be changed.
class ControlView extends WatchUi.View {

    private var _model as Model;

    public function initialize(model as Model) {
        View.initialize();
        _model = model;
    }

    public function onUpdate(dc as Dc) as Void {
        Screen.draw(dc, _model, true);
    }
}

class ControlDelegate extends WatchUi.BehaviorDelegate {

    // Several quick presses become one write.
    private const APPLY_DELAY_MS = 700;

    private var _model as Model;
    private var _transport as Transport;
    private var _timer as Timer.Timer;
    private var _dirty as Boolean = false;
    private var _lastOn as Number = 5;

    public function initialize(model as Model, transport as Transport) {
        BehaviorDelegate.initialize();
        _model = model;
        _transport = transport;
        _timer = new Timer.Timer();
    }

    // UP
    public function onPreviousPage() as Boolean {
        step(1);
        return true;
    }

    // DOWN
    public function onNextPage() as Boolean {
        step(-1);
        return true;
    }

    // START: off, or back to the last level that was on.
    public function onSelect() as Boolean {
        var current = base();
        if (current > 0) {
            _lastOn = current;
            choose(0);
        } else {
            choose(_lastOn);
        }
        return true;
    }

    // BACK: send what is pending, then let the system close the page.
    public function onBack() as Boolean {
        flush();
        return false;
    }

    // MENU, a long press of UP: the way to the target temperature and to diagnostics.
    public function onMenu() as Boolean {
        flush();
        System.println("control: menu");
        var menu = new WatchUi.Menu2({:title => "Thermic"});
        menu.addItem(new WatchUi.MenuItem("Target temp", null, :temperature, null));
        menu.addItem(new WatchUi.MenuItem("Diagnostics", null, :diagnostics, null));
        WatchUi.pushView(menu, new $.MoreDelegate(_model, _transport), WatchUi.SLIDE_LEFT);
        return true;
    }

    public function onApply() as Void {
        flush();
    }

    private function base() as Number {
        if (_model.target != null) {
            return _model.target as Number;
        }
        var level = _model.level();
        return (level != null) ? level : 0;
    }

    private function step(delta as Number) as Void {
        var current = base();
        var value = current + delta;
        if (value < 0) {
            value = 0;
        } else if (value > Protocol.MAX_LEVEL) {
            value = Protocol.MAX_LEVEL;
        }
        if (value == current) {
            // Already at the limit: nothing to send.
            return;
        }
        choose(value);
    }

    private function choose(value as Number) as Void {
        System.println("control: target " + value);
        _model.userPending = true;
        _model.target = value;
        _dirty = true;
        _timer.stop();
        _timer.start(method(:onApply), APPLY_DELAY_MS, false);
        _model.changed();
    }

    private function flush() as Void {
        _timer.stop();
        if (_dirty && _model.target != null) {
            _dirty = false;
            System.println("control: sending level " + _model.target);
            _transport.setLevel(_model.target as Number);
        }
    }
}

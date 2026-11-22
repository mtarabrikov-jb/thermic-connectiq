import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// What the temperature page shows and changes: the target and whether the packs
// regulate to it. Taken from the packs when the page opens.
class TargetState {

    // Degrees Celsius; null while no pack has told its target and none was chosen here.
    public var value as Number? = null;
    public var on as Boolean = false;

    public function initialize(model as Model) {
        for (var i = 0; i < model.packs.size(); i++) {
            var pack = model.packs[i];
            if (value == null && pack.goal != null) {
                value = pack.goal;
            }
            if (pack.regulating == true) {
                on = true;
            }
        }
    }
}

// Target temperature page, opened with MENU from the control page.
class TemperatureView extends WatchUi.View {

    private var _model as Model;
    private var _state as TargetState;

    public function initialize(model as Model, state as TargetState) {
        View.initialize();
        _model = model;
        _state = state;
    }

    public function onUpdate(dc as Dc) as Void {
        Screen.drawTarget(dc, _model, _state);
    }
}

// Each press here leads to one write: UP and DOWN store the target, START stores
// whether the packs regulate to it.
class TemperatureDelegate extends WatchUi.BehaviorDelegate {

    // Several quick presses become one write.
    private const APPLY_DELAY_MS = 700;

    private var _transport as Transport;
    private var _state as TargetState;
    private var _timer as Timer.Timer;
    private var _dirty as Boolean = false;

    public function initialize(transport as Transport, state as TargetState) {
        BehaviorDelegate.initialize();
        _transport = transport;
        _state = state;
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

    // START: regulation on or off. Nothing happens until a target is known: turning it
    // on would make the packs regulate to a value this page cannot show.
    public function onSelect() as Boolean {
        if (_state.value == null) {
            return true;
        }
        flush();
        _state.on = !_state.on;
        System.println("temperature: sending regulation " + (_state.on ? "on" : "off"));
        _transport.setRegulation(_state.on);
        WatchUi.requestUpdate();
        return true;
    }

    // BACK: send what is pending, then let the system close the page.
    public function onBack() as Boolean {
        flush();
        return false;
    }

    public function onApply() as Void {
        flush();
    }

    private function step(delta as Number) as Void {
        var current = _state.value;
        var value = Protocol.clampTarget((current != null) ? current + delta : Protocol.TARGET_DEFAULT);
        if (value == current) {
            // Already at the limit: nothing to send.
            return;
        }
        System.println("temperature: target " + value);
        _state.value = value;
        _dirty = true;
        _timer.stop();
        _timer.start(method(:onApply), APPLY_DELAY_MS, false);
        WatchUi.requestUpdate();
    }

    private function flush() as Void {
        _timer.stop();
        var value = _state.value;
        if (_dirty && value != null) {
            _dirty = false;
            System.println("temperature: sending target " + value);
            _transport.setTarget(value);
        }
    }
}

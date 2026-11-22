import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// An opened widget: the model, the link to the packs and the clock that drives it.
// Not made in glance mode, where neither the memory nor the time for a link is there.
class Session {

    private var _model as Model;
    private var _transport as Transport;
    // The transport has no clock of its own; this one drives its housekeeping.
    private var _timer as Timer.Timer;

    public function initialize() {
        var model = new $.Model();
        // The widget also shows remaining heat time, the temperature inside the pack,
        // the target temperature, what is wrong with a pack and its diagnostics.
        model.details = true;
        var transport = $.makeTransport(model);
        _model = model;
        _transport = transport;
        transport.start();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    public function views() as [Views] or [Views, InputDelegates] {
        return [new $.MainView(_model), new $.MainDelegate(_model, _transport)];
    }

    public function stop() as Void {
        _timer.stop();
        _transport.stop();
    }

    public function onTick() as Void {
        _transport.onTick();
    }
}

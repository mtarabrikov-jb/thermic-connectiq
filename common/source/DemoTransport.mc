import Toybox.Lang;
import Toybox.Timer;

(:demo)
function makeTransport(model as Model) as Transport {
    return new $.DemoTransport(model);
}

// Stand-in for Bluetooth: two made-up packs appear one after another and follow
// the requested level. Used to check the screens without hardware.
(:demo)
class DemoTransport {

    // Tick (1.5 s each) at which the packs change level by themselves.
    private const BUTTON_TICK = 8;

    private var _model as Model;
    private var _timer as Timer.Timer? = null;
    private var _ticks as Number = 0;
    private var _apply as Boolean = false;

    public function initialize(model as Model) {
        _model = model;
    }

    public function start() as Void {
        _model.searching = true;
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 1500, true);
        _timer = timer;
        _model.changed();
    }

    public function stop() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    public function setLevel(level as Number) as Void {
        _model.target = level;
        _apply = true;
    }

    public function onTick() as Void {
        _ticks++;
        if (_ticks == 1) {
            add(3, 87);
        } else if (_ticks == 2) {
            add(3, 64);
            _model.searching = false;
        } else if (_ticks == BUTTON_TICK) {
            // Somebody pressed the button on the packs: they change level on their own.
            setAll(7);
        }
        if (_apply && _model.target != null) {
            _apply = false;
            setAll(_model.target as Number);
            _model.userDone();
            return;
        }
        _model.packReported();
    }

    private function setAll(level as Number) as Void {
        for (var i = 0; i < _model.packs.size(); i++) {
            _model.packs[i].level = level;
        }
    }

    private function add(level as Number, battery as Number) as Void {
        var pack = new Pack();
        pack.level = level;
        pack.battery = battery;
        _model.packs.add(pack);
    }
}

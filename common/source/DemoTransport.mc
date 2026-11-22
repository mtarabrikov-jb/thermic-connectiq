import Toybox.Lang;

(:demo)
function makeTransport(model as Model) as Transport {
    return new $.DemoTransport(model);
}

// Stand-in for Bluetooth: two made-up packs appear one after another and follow
// the requested level. Used to check the screens without hardware.
//
// Like the real transport it has no timer: the host calls onTick() once a second.
(:demo)
class DemoTransport {

    // Seconds after the start at which the two packs appear.
    private const FIRST_PACK_TICK = 2;
    private const SECOND_PACK_TICK = 3;
    // Second at which the first pack changes level by itself.
    private const BUTTON_TICK = 12;
    // Seconds at which the second pack runs low and then drops out, for the alerts.
    private const LOW_TICK = 25;
    private const LOST_TICK = 40;

    private var _model as Model;
    private var _running as Boolean = false;
    private var _ticks as Number = 0;
    private var _apply as Boolean = false;

    public function initialize(model as Model) {
        _model = model;
    }

    public function start() as Void {
        _running = true;
        _model.searching = true;
        _model.changed();
    }

    public function stop() as Void {
        _running = false;
    }

    public function setLevel(level as Number) as Void {
        _model.target = level;
        _apply = true;
    }

    public function setTarget(degrees as Number) as Void {
        for (var i = 0; i < _model.packs.size(); i++) {
            _model.packs[i].goal = degrees;
        }
        _model.changed();
    }

    public function setRegulation(on as Boolean) as Void {
        for (var i = 0; i < _model.packs.size(); i++) {
            _model.packs[i].regulating = on;
        }
        _model.changed();
    }

    public function readDiagnostics() as Void {
        for (var i = 0; i < _model.packs.size(); i++) {
            var pack = _model.packs[i];
            pack.capacity = 2480 + 30 * i;
            pack.current = 312 - 14 * i;
            pack.design = 2600;
            pack.gauge = 24 - i;
            pack.coldest = 12 - i;
            pack.coldestBefore = 8 + i;
        }
        _model.changed();
    }

    public function onTick() as Void {
        if (!_running) {
            return;
        }
        _ticks++;
        if (_ticks == FIRST_PACK_TICK) {
            add(3, 87, 24, 95, 22);
        } else if (_ticks == SECOND_PACK_TICK) {
            add(3, 64, 26, 140, 21);
            _model.searching = false;
        } else if (_ticks == BUTTON_TICK && _model.packs.size() > 0) {
            // Somebody pressed the button on the first pack: it changes level on its
            // own, its gear gets warmer than the other and its heat will not last as long.
            _model.packs[0].level = 7;
            _model.packs[0].remaining = 48;
            for (var i = 0; i < _model.packs.size(); i++) {
                _model.packs[i].temperature = 31 - 4 * i;
            }
        }
        if (_ticks == LOW_TICK && _model.packs.size() > 1) {
            _model.packs[1].battery = 9;
        } else if (_ticks == LOST_TICK && _model.packs.size() > 1) {
            _model.packs = [_model.packs[0]] as Array<Pack>;
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

    private function add(level as Number, battery as Number, temperature as Number,
            remaining as Number, inside as Number) as Void {
        var pack = new Pack();
        pack.level = level;
        pack.battery = battery;
        pack.temperature = temperature;
        if (_model.details) {
            pack.remaining = remaining;
            pack.inside = inside;
            pack.regulating = false;
            pack.goal = Protocol.TARGET_DEFAULT;
            pack.resistance = 845 - 7 * _model.packs.size();
            pack.allowed = true;
        }
        _model.packs.add(pack);
    }
}

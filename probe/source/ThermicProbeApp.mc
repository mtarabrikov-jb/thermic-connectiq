import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

// Probe widget: can this watch find a Therm-ic pack by service UUID, connect to it
// without bonding and write the heat level? Meant to run against pack_emulator.py.
class ThermicProbeApp extends Application.AppBase {

    private var _probe as Probe?;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        _probe = new $.Probe();
        BluetoothLowEnergy.setDelegate(_probe as Probe);
        (_probe as Probe).start();
    }

    public function onStop(state as Dictionary?) as Void {
        if (_probe != null) {
            (_probe as Probe).stop();
        }
        _probe = null;
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var probe = _probe as Probe;
        return [new $.ProbeView(probe), new $.ProbeInput(probe)];
    }
}

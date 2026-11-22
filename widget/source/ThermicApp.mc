import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Widget that controls Therm-ic heated gear from the wrist.
//
// The watch starts it in two ways. For the list of widgets it runs in glance mode with
// 32 KB, and of this app only what is marked (:glance) is loaded: this class and the
// glance view. Opening the widget starts it again in full. So this class stays small
// and touches nothing else before getInitialView(): what an opened widget needs lives
// in Session.
(:glance)
class ThermicApp extends Application.AppBase {

    // The Session of an opened widget; null in glance mode.
    private var _session as Object? = null;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        System.println("app: start");
    }

    public function onStop(state as Dictionary?) as Void {
        System.println("app: stop");
        var session = _session;
        if (session != null) {
            (session as Session).stop();
            _session = null;
        }
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var session = new $.Session();
        _session = session;
        return session.views();
    }

    public function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        System.println("app: glance");
        return [new $.ThermicGlance()];
    }
}

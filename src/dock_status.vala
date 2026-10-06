namespace Singularity.Apps {

    public class DockStatus : Object {
        private const string APP_ID = "dev.sinty.clock";
        private unowned ClockApp app;
        private DBusConnection? bus = null;
        private uint action_sub = 0;
        private uint dock_watch = 0;
        private uint tick_id = 0;
        private uint alarm_id = 0;
        private string last = "";

        public DockStatus(ClockApp app) {
            this.app = app;
        }

        public void start(DBusConnection connection) {
            bus = connection;
            action_sub = bus.signal_subscribe("dev.sinty.Dock", "dev.sinty.Dock", "ActionInvoked", "/dev/sinty/Dock",
                null, DBusSignalFlags.NONE, (c, sender, path, iface, name, parameters) => {
                    string app_id, action_id;
                    parameters.get("(ss)", out app_id, out action_id);
                    if (app_id.down().replace(".desktop", "") == APP_ID) on_action(action_id);
                });
            dock_watch = Bus.watch_name_on_connection(bus, "dev.sinty.Dock", BusNameWatcherFlags.NONE,
                () => { last = ""; update(); }, null);
            app.timer.notify["running"].connect(update);
            app.timer.notify["paused"].connect(update);
            app.alarms.changed.connect(update);
            update();
        }

        public void stop() {
            if (tick_id != 0) Source.remove(tick_id);
            tick_id = 0;
            if (alarm_id != 0) Source.remove(alarm_id);
            alarm_id = 0;
            if (bus != null && action_sub != 0) bus.signal_unsubscribe(action_sub);
            action_sub = 0;
            if (dock_watch != 0) Bus.unwatch_name(dock_watch);
            dock_watch = 0;
        }

        private void on_action(string action_id) {
            switch (action_id) {
                case "timer-pause":
                    if (app.timer.paused) app.timer.resume();
                    else app.timer.pause();
                    break;
                case "timer-stop":
                    app.timer.cancel();
                    break;
                case "next-alarm":
                    app.open_view("alarms");
                    break;
            }
        }

        private static Variant widget(string kind, HashTable<string, Variant> props) {
            var dict = new VariantBuilder(VariantType.VARDICT);
            props.foreach((k, v) => dict.add("{sv}", k, v));
            return new Variant.tuple({ new Variant.string(kind), dict.end() });
        }

        private void update() {
            bool timer_on = app.timer.running || app.timer.paused;
            if (timer_on && tick_id == 0) {
                tick_id = Timeout.add_seconds(1, () => {
                    update();
                    return Source.CONTINUE;
                });
            } else if (!timer_on && tick_id != 0) {
                Source.remove(tick_id);
                tick_id = 0;
            }
            if (bus == null) return;

            var widgets = new VariantBuilder(new VariantType("a(sa{sv})"));
            string key;
            if (timer_on) {
                int64 left = app.timer.remaining_usec();
                string text = Stopwatch.format(left + TimeSpan.SECOND - 1, false);
                double fraction = app.timer.duration > 0 ? (double) left / app.timer.duration : 0;
                key = "timer:%s:%s".printf(text, app.timer.paused.to_string());

                var ring = new HashTable<string, Variant>(str_hash, str_equal);
                ring["id"] = "timer";
                ring["fraction"] = fraction;
                ring["diameter"] = 28;
                ring["color"] = Singularity.Style.StyleManager.get_default().accent_hex;
                ring["tooltip"] = app.timer.paused ? _("Timer paused, %s left").printf(text) : _("Timer, %s left").printf(text);
                widgets.add_value(widget("circular_progress", ring));

                var label = new HashTable<string, Variant>(str_hash, str_equal);
                label["id"] = "timer-left";
                label["label"] = text;
                widgets.add_value(widget("label", label));

                var pause = new HashTable<string, Variant>(str_hash, str_equal);
                pause["id"] = "timer-pause";
                pause["icon"] = app.timer.paused ? "media-playback-start-symbolic" : "media-playback-pause-symbolic";
                pause["tooltip"] = app.timer.paused ? _("Resume") : _("Pause");
                widgets.add_value(widget("button", pause));

                var stop = new HashTable<string, Variant>(str_hash, str_equal);
                stop["id"] = "timer-stop";
                stop["icon"] = "media-playback-stop-symbolic";
                stop["tooltip"] = _("Cancel Timer");
                widgets.add_value(widget("button", stop));
            } else {
                DateTime? when;
                var alarm = app.alarms.next_alarm(out when);
                if (alarm == null) {
                    if (last != "") {
                        last = "";
                        bus.call.begin("dev.sinty.Dock", "/dev/sinty/Dock", "dev.sinty.Dock", "ClearSuffix",
                            new Variant("(s)", APP_ID), null, DBusCallFlags.NO_AUTO_START, 2000, null);
                    }
                    return;
                }
                if (alarm_id != 0) Source.remove(alarm_id);
                int64 wait = when.difference(new DateTime.now_local()) / TimeSpan.SECOND + 1;
                alarm_id = Timeout.add_seconds((uint) wait.clamp(1, 3600), () => {
                    alarm_id = 0;
                    update();
                    return Source.REMOVE;
                });
                string text = "%02d:%02d".printf(when.get_hour(), when.get_minute());
                key = "alarm:" + when.format("%F %R") + alarm.label;
                var bubble = new HashTable<string, Variant>(str_hash, str_equal);
                bubble["id"] = "next-alarm";
                bubble["icon"] = "alarm-symbolic";
                bubble["label"] = text;
                string day = when.format("%A");
                bubble["tooltip"] = alarm.label != ""
                    ? _("Next alarm: %s %s, %s").printf(day, text, alarm.label)
                    : _("Next alarm: %s %s").printf(day, text);
                widgets.add_value(widget("bubble", bubble));
            }
            if (key == last) return;
            last = key;
            bus.call.begin("dev.sinty.Dock", "/dev/sinty/Dock", "dev.sinty.Dock", "SetSuffix",
                new Variant("(sv)", APP_ID, widgets.end()), null, DBusCallFlags.NO_AUTO_START, 2000, null);
        }
    }
}

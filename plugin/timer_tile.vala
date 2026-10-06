using Gtk;
using Singularity;
using Singularity.Apps;

[ModuleInit]
public void peas_register_types(TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Singularity.Plugin), typeof(ClockTimerTile.TimerTilePlugin));
}

namespace ClockTimerTile {

    public class TimerTilePlugin : Object, Singularity.Plugin {
        private const string BUS_NAME = "dev.sinty.clock";
        private const string OBJECT_PATH = "/dev/sinty/clock";
        private const string TIMERS_IFACE = "dev.sinty.Clock.Timers";
        private const int DEFAULT_SECONDS = 300;

        private PluginContext context;
        private QuickTile tile;
        private DBusConnection? bus = null;
        private uint watch_id = 0;
        private uint changed_sub = 0;
        private uint tick_id = 0;
        private string timer_id = "main";
        private string kind = "timer";
        private string status = "idle";
        private int64 end_time = 0;
        private int64 remaining = 0;
        private int64 duration = 0;
        private Label? detail_label = null;
        private Label? detail_phase = null;
        private Box? detail_controls = null;
        private Button indicator;
        private Image indicator_icon;
        private Label indicator_label;
        private static bool styled = false;

        public void activate(PluginContext context) {
            this.context = context;
            string locale_dir = "/usr/share/locale";
            try {
                string exe = FileUtils.read_link("/proc/self/exe");
                locale_dir = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "share", "locale");
            } catch (Error e) {
            }
            Intl.bindtextdomain("singularity-clock", locale_dir);
            Intl.bind_textdomain_codeset("singularity-clock", "UTF-8");
            ensure_style();

            tile = new QuickTile("dev.sinty.clock.timer", _("Timer"), "alarm-symbolic");
            tile.toggleable = false;
            tile.detail_title = _("Timer");
            tile.clicked.connect(on_clicked);
            tile.set_detail_page(() => build_detail());
            context.add_quick_tile(tile);

            build_indicator();
            context.add_panel_widget(indicator, Align.END);
            update_views();

            Bus.get.begin(BusType.SESSION, null, (o, r) => {
                try {
                    bus = Bus.get.end(r);
                } catch (Error e) {
                    warning("clock timer tile: %s", e.message);
                    return;
                }
                changed_sub = bus.signal_subscribe(BUS_NAME, TIMERS_IFACE, "Changed", OBJECT_PATH, null,
                    DBusSignalFlags.NONE, on_changed);
                watch_id = Bus.watch_name_on_connection(bus, BUS_NAME, BusNameWatcherFlags.NONE,
                    () => fetch_state(), () => set_state("main", "timer", "idle", 0, 0, 0));
            });
        }

        public void deactivate() {
            if (tick_id != 0) Source.remove(tick_id);
            tick_id = 0;
            if (watch_id != 0) Bus.unwatch_name(watch_id);
            watch_id = 0;
            if (bus != null && changed_sub != 0) bus.signal_unsubscribe(changed_sub);
            changed_sub = 0;
            context.remove_quick_tile(tile);
            context.remove_panel_widget(indicator);
        }

        public Gtk.Widget? get_settings_widget() {
            return null;
        }

        private void build_indicator() {
            indicator = new Button();
            indicator.has_frame = false;
            indicator.valign = Align.CENTER;
            indicator.visible = false;
            indicator.add_css_class("system-pill-button");
            indicator.add_css_class("clock-timer-indicator");
            var box = new Box(Orientation.HORIZONTAL, 6);
            indicator_icon = new Image.from_icon_name("alarm-symbolic");
            indicator_label = new Label("");
            indicator_label.add_css_class("numeric");
            box.append(indicator_icon);
            box.append(indicator_label);
            indicator.child = box;
            indicator.clicked.connect(() => tile.open_detail_page());
        }

        private void on_clicked() {
            if (status == "idle") call_timer("Start", new Variant("(i)", DEFAULT_SECONDS));
            else call_timer("Cancel", new Variant("(s)", timer_id));
        }

        private void call_timer(string method, Variant parameters) {
            if (bus == null) return;
            bus.call.begin(BUS_NAME, OBJECT_PATH, TIMERS_IFACE, method, parameters,
                null, DBusCallFlags.NONE, 20000, null, (obj, res) => {
                    try {
                        bus.call.end(res);
                    } catch (Error e) {
                        warning("clock timer tile: %s", e.message);
                    }
                });
        }

        private void call_action(string action, Variant? parameter) {
            if (bus == null) return;
            var parameters = new VariantBuilder(new VariantType("av"));
            if (parameter != null) parameters.add("v", parameter);
            var platform = new VariantBuilder(new VariantType("a{sv}"));
            bus.call.begin(BUS_NAME, OBJECT_PATH, "org.freedesktop.Application", "ActivateAction",
                new Variant("(s@av@a{sv})", action, parameters.end(), platform.end()),
                null, DBusCallFlags.NONE, 20000, null, (obj, res) => {
                    try {
                        bus.call.end(res);
                    } catch (Error e) {
                        warning("clock timer tile: %s", e.message);
                    }
                });
        }

        private void fetch_state() {
            if (bus == null) return;
            bus.call.begin(BUS_NAME, OBJECT_PATH, TIMERS_IFACE, "ListTimers", null,
                new VariantType("(a(sssxxx))"), DBusCallFlags.NO_AUTO_START, 5000, null, (obj, res) => {
                    try {
                        var reply = bus.call.end(res);
                        var list = reply.get_child_value(0);
                        if (list.n_children() == 0) {
                            set_state("main", "timer", "idle", 0, 0, 0);
                            return;
                        }
                        string id, k, s;
                        int64 end, left, total;
                        list.get_child_value(0).get("(sssxxx)", out id, out k, out s, out end, out left, out total);
                        set_state(id, k, s, end, left, total);
                    } catch (Error e) {
                        debug("clock timer tile: %s", e.message);
                    }
                });
        }

        private void on_changed(DBusConnection connection, string? sender, string path, string iface,
                                string signal_name, Variant parameters) {
            if (!parameters.is_of_type(new VariantType("(sssxxx)"))) return;
            string id, k, s;
            int64 end, left, total;
            parameters.get("(sssxxx)", out id, out k, out s, out end, out left, out total);
            set_state(id, k, s, end, left, total);
        }

        private void set_state(string id, string k, string s, int64 end, int64 left, int64 total) {
            timer_id = id;
            kind = k;
            status = s;
            end_time = end;
            remaining = left;
            duration = total;
            if (status == "running" && tick_id == 0) {
                tick_id = Timeout.add(250, () => {
                    update_views();
                    return Source.CONTINUE;
                });
            } else if (status != "running" && tick_id != 0) {
                Source.remove(tick_id);
                tick_id = 0;
            }
            update_views();
            refresh_detail();
        }

        private int64 left_usec() {
            return TimerText.remaining(status, end_time, remaining, get_real_time());
        }

        private string phase_text() {
            switch (TimerKind.from_id(kind)) {
                case TimerKind.FOCUS: return _("Focus");
                case TimerKind.SHORT_BREAK: return _("Short Break");
                case TimerKind.LONG_BREAK: return _("Long Break");
                default: return _("Timer");
            }
        }

        private string icon_for_kind() {
            var k = TimerKind.from_id(kind);
            if (k == TimerKind.FOCUS) return "singularity-pomodoro-symbolic";
            if (k.is_break()) return "singularity-pomodoro-break-symbolic";
            return "alarm-symbolic";
        }

        private void update_views() {
            bool active = status != "idle";
            string left = TimerText.compact(left_usec());
            tile.active = active;
            if (status == "running") tile.subtitle = _("%s, %s left").printf(phase_text(), left);
            else if (status == "paused") tile.subtitle = _("%s, paused").printf(left);
            else tile.subtitle = _("5 minutes");

            indicator.visible = active;
            indicator_label.label = left;
            indicator_icon.icon_name = icon_for_kind();
            if (status == "paused") indicator.add_css_class("paused");
            else indicator.remove_css_class("paused");
            string a11y = status == "paused" ? _("%s paused, %s left").printf(phase_text(), left)
                : _("%s, %s left").printf(phase_text(), left);
            indicator.tooltip_text = a11y;
            indicator.update_property(AccessibleProperty.LABEL, a11y, -1);

            if (detail_label != null) detail_label.label = active ? TimerText.countdown(left_usec()) : _("Choose how long");
            if (detail_phase != null) {
                detail_phase.visible = active;
                detail_phase.label = status == "paused" ? _("%s, paused").printf(phase_text()) : phase_text();
            }
        }

        private Gtk.Widget build_detail() {
            var box = new Box(Orientation.VERTICAL, 16);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 12;
            box.margin_end = 12;

            detail_phase = new Label("");
            detail_phase.add_css_class("dim-label");
            box.append(detail_phase);
            detail_label = new Label("");
            detail_label.add_css_class("title-1");
            detail_label.add_css_class("numeric");
            box.append(detail_label);

            detail_controls = new Box(Orientation.HORIZONTAL, 8);
            detail_controls.halign = Align.CENTER;
            box.append(detail_controls);

            var pomodoro = new Button();
            pomodoro.add_css_class("pill");
            pomodoro.add_css_class("suggested-action");
            pomodoro.halign = Align.CENTER;
            var pomodoro_box = new Box(Orientation.HORIZONTAL, 8);
            pomodoro_box.append(new Image.from_icon_name("singularity-pomodoro-symbolic"));
            pomodoro_box.append(new Label(_("Start Pomodoro")));
            pomodoro.child = pomodoro_box;
            pomodoro.tooltip_text = _("Focus sessions with short breaks in between");
            pomodoro.clicked.connect(() => call_timer("StartPomodoro", null));
            box.append(pomodoro);

            var presets = new Grid();
            presets.column_homogeneous = true;
            presets.column_spacing = 6;
            presets.row_spacing = 6;
            int index = 0;
            foreach (int minutes in new int[] { 1, 3, 5, 10, 15, 20, 30, 60 }) {
                int seconds = minutes * 60;
                var button = new Button.with_label(_("%d min").printf(minutes));
                button.add_css_class("pill");
                button.hexpand = true;
                button.clicked.connect(() => call_timer("Start", new Variant("(i)", seconds)));
                presets.attach(button, index % 4, index / 4);
                index++;
            }
            box.append(presets);

            var open = new Button.with_label(_("Open Clock"));
            open.halign = Align.CENTER;
            open.clicked.connect(() => call_action("open-view", new Variant.string("timer")));
            box.append(open);

            box.destroy.connect(() => {
                detail_label = null;
                detail_phase = null;
                detail_controls = null;
            });
            update_views();
            refresh_detail();
            return box;
        }

        private void refresh_detail() {
            if (detail_controls == null) return;
            Widget? child;
            while ((child = detail_controls.get_first_child()) != null) detail_controls.remove(child);
            detail_controls.visible = status != "idle";
            if (status == "idle") return;
            var pause = new Button.with_label(status == "paused" ? _("Resume") : _("Pause"));
            pause.add_css_class("pill");
            pause.clicked.connect(() => call_timer(status == "paused" ? "Resume" : "Pause", new Variant("(s)", timer_id)));
            detail_controls.append(pause);
            var cancel = new Button.with_label(_("Cancel"));
            cancel.add_css_class("pill");
            cancel.add_css_class("destructive-action");
            cancel.clicked.connect(() => call_timer("Cancel", new Variant("(s)", timer_id)));
            detail_controls.append(cancel);
        }

        private static void ensure_style() {
            if (styled) return;
            var display = Gdk.Display.get_default();
            if (display == null) return;
            styled = true;
            var provider = new CssProvider();
            provider.load_from_string(".clock-timer-indicator.paused label { opacity: 0.6; }");
            StyleContext.add_provider_for_display(display, provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
    }
}

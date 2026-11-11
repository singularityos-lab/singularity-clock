namespace Singularity.Apps {

    public class ClockApp : Singularity.Application {
        public GLib.Settings settings { get; private set; }
        public AlarmStore alarms { get; private set; }
        public Ringer ringer { get; private set; }
        public CountdownTimer timer { get; private set; }
        public Stopwatch stopwatch { get; private set; }

        private ClockWindow? window = null;
        private bool held = false;
        private DockStatus dock_status;
        private SimpleAction timer_state;
        private TimerService? timer_service = null;
        private uint timer_service_id = 0;
        public PomodoroCycle pomodoro { get; private set; default = new PomodoroCycle(); }

        public ClockApp() {
            Object(application_id: "dev.sinty.clock",
                   flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        }

        private void sync_timer_actions() {
            ((SimpleAction) lookup_action("stopwatch-lap")).set_enabled(stopwatch.running);
            ((SimpleAction) lookup_action("stopwatch-reset")).set_enabled(!stopwatch.running && stopwatch.elapsed_usec() > 0);
            ((SimpleAction) lookup_action("timer-pause")).set_enabled(timer.running || timer.paused);
            ((SimpleAction) lookup_action("timer-cancel")).set_enabled(timer.running || timer.paused);
        }

        protected override void startup() {
            base.startup();
            setup_styles();
            settings = new GLib.Settings("dev.sinty.clock");
            ringer = new Ringer(this);
            alarms = new AlarmStore(settings);
            timer = new CountdownTimer();
            stopwatch = new Stopwatch();
            ClockIntents.install(this);

            alarms.ringing.connect((alarm) => {
                if (!run_alarm_action(alarm)) ring_alarm(alarm);
            });
            timer.finished.connect(on_timer_finished);
            settings.bind("pomodoro-focus-minutes", pomodoro, "focus-minutes", SettingsBindFlags.GET);
            settings.bind("pomodoro-short-break-minutes", pomodoro, "short-break-minutes", SettingsBindFlags.GET);
            settings.bind("pomodoro-long-break-minutes", pomodoro, "long-break-minutes", SettingsBindFlags.GET);
            alarms.changed.connect(update_hold);
            alarms.changed.connect(ensure_autostart);
            timer.notify["running"].connect(update_hold);
            stopwatch.notify["running"].connect(update_hold);
            ringer.notify["ringing-id"].connect(update_hold);

            var menu = new GLib.Menu();
            var file_menu = new GLib.Menu();
            var file_new = new GLib.Menu();
            file_new.append(_("New Alarm…"), "win.new-alarm");
            file_new.append(_("Add City…"), "win.add-city");
            file_menu.append_section(null, file_new);
            var file_close = new GLib.Menu();
            file_close.append(_("Close Window"), "win.close");
            file_close.append(_("Quit"), "app.quit");
            file_menu.append_section(null, file_close);
            menu.append_submenu(_("File"), file_menu);
            var edit_menu = new GLib.Menu();
            edit_menu.append(_("Settings"), "app.settings");
            menu.append_submenu(_("Edit"), edit_menu);
            var view_menu = new GLib.Menu();
            view_menu.append(_("Alarms"), "win.view::alarms");
            view_menu.append(_("World"), "win.view::world");
            view_menu.append(_("Stopwatch"), "win.view::stopwatch");
            view_menu.append(_("Timer"), "win.view::timer");
            menu.append_submenu(_("View"), view_menu);
            var stopwatch_menu = new GLib.Menu();
            stopwatch_menu.append(_("Start or Stop"), "app.stopwatch-toggle");
            stopwatch_menu.append(_("Lap"), "app.stopwatch-lap");
            stopwatch_menu.append(_("Reset"), "app.stopwatch-reset");
            menu.append_submenu(_("Stopwatch"), stopwatch_menu);
            var timer_menu = new GLib.Menu();
            timer_menu.append(_("Pause or Resume"), "app.timer-pause");
            timer_menu.append(_("Cancel Timer"), "app.timer-cancel");
            menu.append_submenu(_("Timer"), timer_menu);
            set_menubar(menu);

            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => quit());
            add_action(quit_action);
            var stop_action = new SimpleAction("stop-ringing", VariantType.STRING);
            stop_action.activate.connect(() => ringer.stop());
            add_action(stop_action);
            var snooze_action = new SimpleAction("snooze", VariantType.STRING);
            snooze_action.activate.connect((param) => {
                ringer.stop();
                alarms.snooze(param.get_string(), settings.get_int("snooze-minutes"));
            });
            add_action(snooze_action);
            var show_action = new SimpleAction("show", null);
            show_action.activate.connect(() => activate());
            add_action(show_action);
            var settings_action = new SimpleAction("settings", null);
            settings_action.activate.connect(() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync(BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings("dev.sinty.clock");
                } catch (Error e) {
                    warning("Failed to open settings: %s", e.message);
                }
            });
            add_action(settings_action);
            var stopwatch_toggle = new SimpleAction("stopwatch-toggle", null);
            stopwatch_toggle.activate.connect(() => {
                if (stopwatch.running) stopwatch.stop();
                else stopwatch.start();
            });
            add_action(stopwatch_toggle);
            var stopwatch_lap = new SimpleAction("stopwatch-lap", null);
            stopwatch_lap.activate.connect(() => { if (stopwatch.running) stopwatch.lap(); });
            add_action(stopwatch_lap);
            var stopwatch_reset = new SimpleAction("stopwatch-reset", null);
            stopwatch_reset.activate.connect(() => stopwatch.reset());
            add_action(stopwatch_reset);
            var timer_pause = new SimpleAction("timer-pause", null);
            timer_pause.activate.connect(() => {
                if (timer.paused) timer.resume();
                else timer.pause();
            });
            add_action(timer_pause);
            var timer_cancel = new SimpleAction("timer-cancel", null);
            timer_cancel.activate.connect(() => cancel_timer());
            add_action(timer_cancel);
            var timer_start = new SimpleAction("timer-start", VariantType.INT32);
            timer_start.activate.connect((param) => start_timer(param.get_int32()));
            add_action(timer_start);
            var pomodoro_start = new SimpleAction("pomodoro-start", null);
            pomodoro_start.activate.connect(() => start_pomodoro());
            add_action(pomodoro_start);
            var open_view_action = new SimpleAction("open-view", VariantType.STRING);
            open_view_action.activate.connect((param) => open_view(param.get_string()));
            add_action(open_view_action);
            timer_state = new SimpleAction.stateful("timer-state", null, timer_state_value());
            timer_state.set_enabled(false);
            add_action(timer_state);
            timer.notify["running"].connect(sync_timer_state);
            timer.notify["paused"].connect(sync_timer_state);
            stopwatch.notify["running"].connect(sync_timer_actions);
            stopwatch.laps_changed.connect(sync_timer_actions);
            timer.notify["running"].connect(sync_timer_actions);
            timer.notify["paused"].connect(sync_timer_actions);
            sync_timer_actions();
            set_accels_for_action("app.settings", {"<Control>comma"});
            set_accels_for_action("win.close", {"<Control>w"});
            set_accels_for_action("win.view::alarms", {"<Control>1"});
            set_accels_for_action("win.view::world", {"<Control>2"});
            set_accels_for_action("win.view::stopwatch", {"<Control>3"});
            set_accels_for_action("win.view::timer", {"<Control>4"});
            set_accels_for_action("win.new-alarm", {"<Control>n"});

            update_hold();
            ensure_autostart();

            dock_status = new DockStatus(this);
            var connection = get_dbus_connection();
            if (connection != null) dock_status.start(connection);
        }

        protected override void shutdown() {
            if (dock_status != null) dock_status.stop();
            base.shutdown();
        }

        protected override int command_line(ApplicationCommandLine command_line) {
            string[] args = command_line.get_arguments();
            if ("--new-timer" in args) open_view("timer");
            else if ("--new-alarm" in args) open_view("new-alarm");
            else if ("--stopwatch" in args) open_view("stopwatch");
            else if (!("--background" in args)) activate();
            return 0;
        }

        public void open_view(string view) {
            activate();
            if (window.is_active) {
                show_view(view);
                return;
            }
            var target = window;
            ulong handler = 0;
            uint fallback = 0;
            handler = target.notify["is-active"].connect(() => {
                if (!target.is_active) return;
                target.disconnect(handler);
                handler = 0;
                if (fallback != 0) Source.remove(fallback);
                fallback = 0;
                show_view(view);
            });
            fallback = Timeout.add(1500, () => {
                fallback = 0;
                if (handler != 0) target.disconnect(handler);
                handler = 0;
                show_view(view);
                return Source.REMOVE;
            });
        }

        private void show_view(string view) {
            if (window == null) return;
            if (view == "new-alarm") ((GLib.ActionGroup) window).activate_action("new-alarm", null);
            else ((GLib.ActionGroup) window).activate_action("view", new Variant.string(view));
        }

        public void start_timer(int seconds) {
            if (seconds <= 0) return;
            pomodoro.reset();
            settings.set_int("timer-seconds", seconds);
            timer.start(seconds);
            sync_timer_state();
        }

        public void start_pomodoro() {
            ringer.stop();
            pomodoro.reset();
            timer.start(pomodoro.minutes_for(TimerKind.FOCUS) * 60, TimerKind.FOCUS);
            sync_timer_state();
        }

        public void cancel_timer() {
            pomodoro.reset();
            timer.cancel();
        }

        private void on_timer_finished() {
            TimerKind kind = timer.kind;
            if (timer_service != null) timer_service.finished(TimerService.MAIN_ID, kind.to_id());
            TimerKind next;
            if (pomodoro.next_after(kind, out next)) {
                timer.start(pomodoro.minutes_for(next) * 60, next);
                sync_timer_state();
                ringer.ring("timer", _("Focus Session Done"),
                    ngettext("Take a break for %d minute", "Take a break for %d minutes", pomodoro.minutes_for(next))
                        .printf(pomodoro.minutes_for(next)), false, 1);
                return;
            }
            if (kind.is_break()) {
                ringer.ring("timer", _("Break Is Over"), _("Start the next focus session when you are ready"), false, 1);
                return;
            }
            ringer.ring("timer", _("Timer"), _("Time is up"), false, settings.get_int("ring-minutes"));
        }

        public override bool dbus_register(DBusConnection connection, string object_path) throws Error {
            if (!base.dbus_register(connection, object_path)) return false;
            timer_service = new TimerService(this);
            timer_service_id = connection.register_object(object_path, timer_service);
            return true;
        }

        public override void dbus_unregister(DBusConnection connection, string object_path) {
            if (timer_service_id != 0) connection.unregister_object(timer_service_id);
            timer_service_id = 0;
            base.dbus_unregister(connection, object_path);
        }

        private Variant timer_state_value() {
            string status = timer.paused ? "paused" : (timer.running ? "running" : "idle");
            int64 remaining = timer.remaining_usec();
            int64 end = timer.running && !timer.paused ? get_real_time() + remaining : 0;
            return new Variant("(sxxx)", status, end, remaining, timer.duration);
        }

        private void sync_timer_state() {
            if (timer_state != null) timer_state.set_state(timer_state_value());
            if (timer_service != null) timer_service.emit_changed();
        }

        protected override void activate() {
            if (window == null) {
                window = new ClockWindow(this);
                window.close_request.connect(() => {
                    window = null;
                    return false;
                });
            }
            window.present();
        }

        private void ring_alarm(Alarm alarm) {
            string title = alarm.label != "" ? alarm.label : _("Alarm");
            ringer.ring(alarm.id, title, alarm.time_text(), true, settings.get_int("ring-minutes"));
        }

        private bool run_alarm_action(Alarm alarm) {
            string app_id, action, target;
            if (!settings.get_value("alarm-actions").lookup(alarm.id, "(sss)", out app_id, out action, out target)) return false;
            var connection = get_dbus_connection();
            if (connection == null || !GLib.Application.id_is_valid(app_id) || action == "") return false;
            string path = "/" + app_id.replace(".", "/").replace("-", "_");
            var parameters = new VariantBuilder(new VariantType("av"));
            parameters.add("v", new Variant.string(target));
            var platform = new VariantBuilder(new VariantType("a{sv}"));
            hold();
            connection.call.begin(app_id, path, "org.freedesktop.Application", "ActivateAction",
                                  new Variant("(s@av@a{sv})", action, parameters.end(), platform.end()),
                                  null, DBusCallFlags.NONE, 20000, null, (obj, res) => {
                try {
                    connection.call.end(res);
                } catch (Error e) {
                    warning("Clock: cannot start the alarm in %s: %s", app_id, e.message);
                    ring_alarm(alarm);
                }
                release();
            });
            return true;
        }

        private void ensure_autostart() {
            if (alarms.alarms.size == 0) return;
            string dir = Path.build_filename(Environment.get_user_config_dir(), "autostart");
            string path = Path.build_filename(dir, "dev.sinty.clock-alarms.desktop");
            if (FileUtils.test(path, FileTest.EXISTS)) return;
            string exe = "singularity-clock";
            try {
                exe = FileUtils.read_link("/proc/self/exe");
            } catch (FileError e) { }
            var entry = new KeyFile();
            entry.set_string("Desktop Entry", "Type", "Application");
            entry.set_string("Desktop Entry", "Name", _("Clock Alarms"));
            entry.set_string("Desktop Entry", "Comment", _("Ring alarms and timers while Clock is closed"));
            entry.set_string("Desktop Entry", "Exec", "%s --background".printf(GLib.Shell.quote(exe)));
            entry.set_string("Desktop Entry", "Icon", "dev.sinty.clock");
            try {
                DirUtils.create_with_parents(dir, 0755);
                entry.save_to_file(path);
            } catch (Error e) {
                warning("Clock: cannot register alarms at login: %s", e.message);
            }
        }

        private void update_hold() {
            bool needed = alarms.any_enabled() || timer.running || stopwatch.running || ringer.ringing_id != null;
            if (needed && !held) {
                hold();
                held = true;
            } else if (!needed && held) {
                held = false;
                release();
            }
        }

        public static int main(string[] args) {
            Intl.setlocale(GLib.LocaleCategory.ALL, "");
            string locale_dir = "/usr/share/locale";
            try {
                string exe = GLib.FileUtils.read_link("/proc/self/exe");
                locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
            } catch (GLib.Error e) { }
            Intl.bindtextdomain("singularity-clock", locale_dir);
            Intl.bind_textdomain_codeset("singularity-clock", "UTF-8");
            Intl.textdomain("singularity-clock");

            var app = new ClockApp();
            return app.run(args);
        }

        private void setup_styles() {
            var provider = new Gtk.CssProvider();
            provider.load_from_string(CLOCK_CSS);
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 2);
        }

        private const string CLOCK_CSS = """
.clock-view {
    padding: 24px;
}

.clock-hero {
    font-size: 64px;
    font-weight: 300;
    font-feature-settings: "tnum";
}

.clock-hero-long {
    font-size: 44px;
}

.singularity-app:not(.ssd-mode) .clock-pages > * {
    padding-top: 44px;
}

.clock-hero-caption {
    opacity: 0.6;
}

.clock-alarm-row .title,
.clock-city-time {
    font-size: 26px;
    font-weight: 300;
    font-feature-settings: "tnum";
}

.clock-alarm-row.disabled .title {
    opacity: 0.45;
}

.clock-day-toggle {
    min-width: 40px;
    min-height: 40px;
    border-radius: 999px;
    padding: 0;
}

.clock-lap-time {
    font-feature-settings: "tnum";
}
""";
    }
}

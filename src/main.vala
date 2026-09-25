namespace Singularity.Apps {

    public class ClockApp : Singularity.Application {
        public GLib.Settings settings { get; private set; }
        public AlarmStore alarms { get; private set; }
        public Ringer ringer { get; private set; }
        public CountdownTimer timer { get; private set; }
        public Stopwatch stopwatch { get; private set; }

        private ClockWindow? window = null;
        private bool held = false;

        public ClockApp() {
            Object(application_id: "dev.sinty.clock",
                   flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        }

        protected override void startup() {
            base.startup();
            setup_styles();
            settings = new GLib.Settings("dev.sinty.clock");
            ringer = new Ringer(this);
            alarms = new AlarmStore(settings);
            timer = new CountdownTimer();
            stopwatch = new Stopwatch();

            alarms.ringing.connect((alarm) => {
                string title = alarm.label != "" ? alarm.label : _("Alarm");
                ringer.ring(alarm.id, title, alarm.time_text(), true, settings.get_int("ring-minutes"));
            });
            timer.finished.connect(() => {
                ringer.ring("timer", _("Timer"), _("Time is up"), false, settings.get_int("ring-minutes"));
            });
            alarms.changed.connect(update_hold);
            alarms.changed.connect(ensure_autostart);
            timer.notify["running"].connect(update_hold);
            stopwatch.notify["running"].connect(update_hold);
            ringer.notify["ringing-id"].connect(update_hold);

            var menu = new GLib.Menu();
            var file_menu = new GLib.Menu();
            file_menu.append(_("Quit"), "app.quit");
            menu.append_submenu(_("File"), file_menu);
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

            update_hold();
            ensure_autostart();
        }

        protected override int command_line(ApplicationCommandLine command_line) {
            string[] args = command_line.get_arguments();
            if (!("--background" in args)) activate();
            return 0;
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

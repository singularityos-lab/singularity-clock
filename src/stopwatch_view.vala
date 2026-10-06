using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class StopwatchView : Box {
        private unowned Stopwatch stopwatch;
        private Label time;
        private Button start_button;
        private Button lap_button;
        private PreferencesGroup laps;

        public StopwatchView(ClockApp app) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            stopwatch = app.stopwatch;

            var body = new Box(Orientation.VERTICAL, 24);
            body.add_css_class("clock-view");

            time = new Label("");
            time.add_css_class("clock-hero");
            time.margin_top = 24;
            body.append(time);

            var buttons = new Box(Orientation.HORIZONTAL, 12);
            buttons.halign = Align.CENTER;
            start_button = new Button();
            start_button.add_css_class("pill");
            start_button.clicked.connect(() => {
                if (stopwatch.running) stopwatch.stop();
                else stopwatch.start();
                update_buttons();
            });
            lap_button = new Button();
            lap_button.add_css_class("pill");
            lap_button.clicked.connect(() => {
                if (stopwatch.running) stopwatch.lap();
                else stopwatch.reset();
                update_buttons();
            });
            buttons.append(start_button);
            buttons.append(lap_button);
            body.append(buttons);

            laps = new PreferencesGroup(_("Laps"));
            body.append(laps);

            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = body;
            append(scroll);

            stopwatch.tick.connect(update_time);
            stopwatch.laps_changed.connect(rebuild_laps);
            stopwatch.laps_changed.connect(update_buttons);
            stopwatch.notify["running"].connect(update_buttons);
            update_time();
            update_buttons();
            rebuild_laps();
        }

        private void update_time() {
            time.label = Stopwatch.format(stopwatch.elapsed_usec(), true);
        }

        private void update_buttons() {
            start_button.label = stopwatch.running ? _("Stop") : _("Start");
            if (stopwatch.running) {
                start_button.remove_css_class("suggested-action");
                start_button.add_css_class("destructive-action");
            } else {
                start_button.remove_css_class("destructive-action");
                start_button.add_css_class("suggested-action");
            }
            lap_button.label = stopwatch.running ? _("Lap") : _("Reset");
            lap_button.sensitive = stopwatch.running || stopwatch.elapsed_usec() > 0;
        }

        private void rebuild_laps() {
            laps.clear();
            int number = stopwatch.laps.size;
            foreach (int64? lap in stopwatch.laps) {
                var row = new ActionRow(_("Lap %d").printf(number--));
                var value = new Label(Stopwatch.format(lap, true));
                value.add_css_class("clock-lap-time");
                row.add_suffix(value);
                laps.add_row(row);
            }
            laps.visible = stopwatch.laps.size > 0;
        }
    }
}

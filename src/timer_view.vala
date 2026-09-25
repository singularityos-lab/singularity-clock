using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class TimerView : Box {
        private unowned ClockApp app;
        private unowned CountdownTimer timer;
        private Stack pages;
        private TimePicker picker;
        private Button start_button;
        private CircularProgress progress;
        private Label remaining;
        private Button pause_button;

        public TimerView(ClockApp app) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.app = app;
            timer = app.timer;

            pages = new Stack();
            pages.transition_type = StackTransitionType.CROSSFADE;
            pages.vexpand = true;
            pages.add_named(build_setup(), "setup");
            pages.add_named(build_running(), "running");
            append(pages);

            timer.tick.connect(update_running);
            timer.notify["running"].connect(update_page);
            timer.notify["paused"].connect(update_running);
            update_page();
        }

        private Widget build_setup() {
            var body = new Box(Orientation.VERTICAL, 24);
            body.add_css_class("clock-view");
            body.valign = Align.CENTER;

            int saved = app.settings.get_int("timer-seconds") / 60;
            picker = new TimePicker("%02d:%02d".printf(saved / 60, saved % 60));
            picker.halign = Align.CENTER;
            picker.changed.connect(update_start_button);
            var caption = new Label(_("Hours and minutes"));
            caption.add_css_class("dim-label");
            body.append(picker);
            body.append(caption);

            var presets = new FlowBox();
            presets.halign = Align.CENTER;
            presets.selection_mode = SelectionMode.NONE;
            presets.max_children_per_line = 4;
            presets.column_spacing = 8;
            presets.row_spacing = 8;
            foreach (int preset in new int[] { 1, 3, 5, 10, 15, 30, 45, 60 }) {
                int total = preset * 60;
                var button = new Button.with_label(_("%d min").printf(preset));
                button.add_css_class("pill");
                button.clicked.connect(() => start(total));
                presets.append(button);
            }
            body.append(presets);

            start_button = new Button.with_label(_("Start"));
            start_button.add_css_class("pill");
            start_button.add_css_class("suggested-action");
            start_button.halign = Align.CENTER;
            start_button.clicked.connect(() => start(picker_seconds()));
            body.append(start_button);
            update_start_button();
            return body;
        }

        private int picker_seconds() {
            string[] parts = picker.time.split(":");
            int hours = int.parse(parts[0]);
            int minutes = parts.length > 1 ? int.parse(parts[1]) : 0;
            return hours * 3600 + minutes * 60;
        }

        private Widget build_running() {
            var body = new Box(Orientation.VERTICAL, 32);
            body.add_css_class("clock-view");
            body.valign = Align.CENTER;

            progress = new CircularProgress(260);
            progress.color = Singularity.Style.StyleManager.get_default().accent_hex;
            remaining = new Label("");
            remaining.add_css_class("clock-hero");
            var dial = new Overlay();
            dial.halign = Align.CENTER;
            dial.child = progress;
            dial.add_overlay(remaining);
            body.append(dial);

            var buttons = new Box(Orientation.HORIZONTAL, 12);
            buttons.halign = Align.CENTER;
            pause_button = new Button();
            pause_button.add_css_class("pill");
            pause_button.clicked.connect(() => {
                if (timer.paused) timer.resume();
                else timer.pause();
            });
            var cancel = new Button.with_label(_("Cancel"));
            cancel.add_css_class("pill");
            cancel.add_css_class("destructive-action");
            cancel.clicked.connect(() => timer.cancel());
            buttons.append(pause_button);
            buttons.append(cancel);
            body.append(buttons);
            return body;
        }

        private void start(int total_seconds) {
            if (total_seconds <= 0) return;
            app.settings.set_int("timer-seconds", total_seconds);
            timer.start(total_seconds);
        }

        private void update_start_button() {
            start_button.sensitive = picker_seconds() > 0;
        }

        private void update_page() {
            pages.visible_child_name = timer.running || timer.paused ? "running" : "setup";
            update_running();
        }

        private void update_running() {
            int64 left = timer.remaining_usec();
            progress.fraction = timer.duration > 0 ? (double) left / timer.duration : 0;
            remaining.label = Stopwatch.format(left + TimeSpan.SECOND - 1, false);
            pause_button.label = timer.paused ? _("Resume") : _("Pause");
            if (!timer.running && !timer.paused) pages.visible_child_name = "setup";
        }
    }
}

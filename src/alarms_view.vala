using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class AlarmsView : Box {
        private unowned ClockApp app;
        private Stack content;
        private PreferencesGroup group;

        public AlarmsView(ClockApp app) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.app = app;

            content = new Stack();
            content.vexpand = true;

            var empty = new WelcomePage();
            empty.is_section = true;
            empty.app_icon_name = "dev.sinty.clock";
            empty.title = _("No Alarms");
            empty.subtitle = _("Alarms ring even when Clock is closed");
            empty.add_action("dev.sinty.clock", _("New Alarm"), _("Choose a time, the days it repeats and a label"), () => add_alarm());
            content.add_named(empty, "empty");

            group = new PreferencesGroup();
            var list_box = new Box(Orientation.VERTICAL, 0);
            list_box.add_css_class("clock-view");
            list_box.append(group);
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = list_box;
            content.add_named(scroll, "list");
            append(content);

            app.alarms.changed.connect(rebuild);
            rebuild();
        }

        public void add_alarm() {
            open_dialog(null);
        }

        private void open_dialog(Alarm? alarm) {
            var dialog = new AlarmDialog(app, alarm);
            dialog.transient_for = get_root() as Gtk.Window;
            dialog.open_dialog();
        }

        private void rebuild() {
            group.clear();
            foreach (var alarm in app.alarms.alarms) group.add_row(build_row(alarm));
            content.visible_child_name = app.alarms.alarms.size == 0 ? "empty" : "list";
        }

        private ActionRow build_row(Alarm alarm) {
            string subtitle = alarm.label != "" ? "%s  ·  %s".printf(alarm.days_text(), alarm.label) : alarm.days_text();
            if (alarm.enabled && app.alarms.is_skipped(alarm, alarm.next_ring(new DateTime.now_local()))) {
                subtitle = _("%s  ·  Next ring skipped").printf(subtitle);
            }
            var row = new ActionRow(alarm.time_text(), subtitle);
            row.add_css_class("clock-alarm-row");
            if (!alarm.enabled) row.add_css_class("disabled");

            var toggle = new Switch();
            toggle.valign = Align.CENTER;
            toggle.active = alarm.enabled;
            toggle.notify["active"].connect(() => {
                if (alarm.enabled == toggle.active) return;
                alarm.enabled = toggle.active;
                app.alarms.update(alarm);
            });

            var edit = new Button.from_icon_name("document-edit-symbolic");
            edit.add_css_class("flat");
            edit.valign = Align.CENTER;
            edit.tooltip_text = _("Edit");
            edit.clicked.connect(() => open_dialog(alarm));

            var remove = new Button.from_icon_name("user-trash-symbolic");
            remove.add_css_class("flat");
            remove.valign = Align.CENTER;
            remove.tooltip_text = _("Delete");
            remove.clicked.connect(() => app.alarms.remove(alarm.id));

            row.add_suffix(edit);
            row.add_suffix(remove);
            row.add_suffix(toggle);
            return row;
        }
    }

    public class AlarmDialog : AppDialog {
        private unowned ClockApp app;
        private Alarm? alarm;
        private TimePicker picker;
        private ToggleButton[] day_buttons = {};
        private EntryRow label_entry;

        public AlarmDialog(ClockApp app, Alarm? alarm) {
            base(app, true);
            this.app = app;
            this.alarm = alarm;
            set_title(alarm == null ? _("New Alarm") : _("Edit Alarm"));
            set_default_size(380, -1);

            var body = new Box(Orientation.VERTICAL, 16);
            body.margin_top = 12;
            body.margin_bottom = 16;
            body.margin_start = 20;
            body.margin_end = 20;

            picker = new TimePicker(alarm != null ? alarm.time_text() : "07:00");
            picker.halign = Align.CENTER;
            body.append(picker);

            var days = new Box(Orientation.HORIZONTAL, 6);
            days.halign = Align.CENTER;
            string[] names = { _("M"), _("T"), _("W"), _("T"), _("F"), _("S"), _("S") };
            for (int i = 0; i < 7; i++) {
                var toggle = new ToggleButton.with_label(names[i]);
                toggle.add_css_class("clock-day-toggle");
                toggle.active = alarm != null && (alarm.days & (Alarm.MONDAY << i)) != 0;
                days.append(toggle);
                day_buttons += toggle;
            }
            body.append(days);

            label_entry = new EntryRow(_("Label"));
            label_entry.text = alarm != null ? alarm.label : "";
            var details = new PreferencesGroup();
            details.add_row(label_entry);
            body.append(details);

            var actions = new Box(Orientation.HORIZONTAL, 8);
            actions.halign = Align.END;
            var cancel = new Button.with_label(_("Cancel"));
            cancel.clicked.connect(() => close_dialog());
            set_cancel_button(cancel);
            var save = new Button.with_label(_("Save"));
            save.add_css_class("suggested-action");
            save.clicked.connect(on_save);
            actions.append(cancel);
            actions.append(save);
            body.append(actions);

            content_box.append(body);
        }

        private void on_save() {
            string[] parts = picker.time.split(":");
            int hour = int.parse(parts[0]).clamp(0, 23);
            int minute = parts.length > 1 ? int.parse(parts[1]).clamp(0, 59) : 0;
            uint days = 0;
            for (int i = 0; i < 7; i++) {
                if (day_buttons[i].active) days |= Alarm.MONDAY << i;
            }
            string label = label_entry.text.strip();
            if (alarm == null) {
                app.alarms.add(hour, minute, days, label);
            } else {
                alarm.hour = hour;
                alarm.minute = minute;
                alarm.days = days;
                alarm.label = label;
                alarm.enabled = true;
                app.alarms.update(alarm);
            }
            close_dialog();
        }
    }
}

using Gtk;
using Singularity;

namespace SingularityClockWidget {

    public class WorldProvider : Object, OverviewWidgetProvider {
        public string id { get { return "clock.world"; } }
        public string provider_id { get { return "dev.sinty.clock"; } }
        public string display_name { get { return _("World Clocks"); } }
        public string icon_name { get { return "preferences-system-time-symbolic"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[2];
                    _sizes[0] = WidgetSize(2, 1);
                    _sizes[1] = WidgetSize(2, 2);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance(string instance_id, WidgetSize size, Variant? config) {
            return new WorldInstance(size);
        }
    }

    public class WorldInstance : Box {
        private WidgetSize size;
        private GLib.Settings? settings = null;
        private Box cities;
        private Box? alarm_box = null;
        private uint tick_id = 0;
        private bool updating = false;

        public WorldInstance(WidgetSize size) {
            Object(orientation: Orientation.VERTICAL, spacing: 8);
            this.size = size;
            add_css_class("overview-widget-card");
            add_css_class("overview-world-clocks");
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;

            var inner = new Box(Orientation.VERTICAL, 8);
            inner.margin_top = 12;
            inner.margin_bottom = 12;
            inner.margin_start = 16;
            inner.margin_end = 16;
            inner.vexpand = true;
            append(inner);

            cities = new Box(Orientation.VERTICAL, 4);
            cities.vexpand = true;
            cities.valign = Align.CENTER;
            var cities_click = new GestureClick();
            cities_click.released.connect(() => open_view("world"));
            cities.add_controller(cities_click);
            cities.cursor = new Gdk.Cursor.from_name("pointer", null);
            inner.append(cities);

            if (size.h >= 2) {
                inner.append(new Separator(Orientation.HORIZONTAL));
                alarm_box = new Box(Orientation.HORIZONTAL, 12);
                alarm_box.valign = Align.CENTER;
                inner.append(alarm_box);
            }

            var source = SettingsSchemaSource.get_default();
            if (source != null && source.lookup("dev.sinty.clock", true) != null) {
                settings = new GLib.Settings("dev.sinty.clock");
                settings.changed.connect((key) => {
                    if (key == "world-clocks" || key == "alarms" || key == "skipped-alarms") {
                        Idle.add(() => {
                            refresh();
                            return Source.REMOVE;
                        });
                    }
                });
            }
            refresh();
            uint delay = 60000 - (uint) ((get_real_time() / 1000) % 60000);
            tick_id = Timeout.add(uint.max(500, delay), () => {
                refresh();
                tick_id = Timeout.add_seconds(60, () => {
                    refresh();
                    return Source.CONTINUE;
                });
                return Source.REMOVE;
            });
            destroy.connect(() => {
                if (tick_id != 0) Source.remove(tick_id);
                tick_id = 0;
            });
        }

        private static void clear(Box box) {
            Widget? child;
            while ((child = box.get_first_child()) != null) box.remove(child);
        }

        private static string city_name(string zone) {
            string[] parts = zone.split("/");
            return parts[parts.length - 1].replace("_", " ");
        }

        private static string offset_text(DateTime local, DateTime other) {
            int64 diff = (other.get_utc_offset() - local.get_utc_offset()) / TimeSpan.MINUTE;
            if (diff == 0) return _("Same time");
            int64 hours = diff.abs() / 60;
            int64 minutes = diff.abs() % 60;
            string amount = minutes == 0 ? _("%lld h").printf(hours) : _("%lld h %lld min").printf(hours, minutes);
            return diff > 0 ? _("%s ahead").printf(amount) : _("%s behind").printf(amount);
        }

        private Box city_row(string name, string detail, DateTime time, bool emphasis) {
            var row = new Box(Orientation.HORIZONTAL, 8);
            var texts = new Box(Orientation.VERTICAL, 0);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            var title = new Label(name);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class(emphasis ? "heading" : "body");
            texts.append(title);
            var sub = new Label(detail);
            sub.xalign = 0;
            sub.ellipsize = Pango.EllipsizeMode.END;
            sub.add_css_class("caption");
            sub.add_css_class("dim-label");
            texts.append(sub);
            row.append(texts);
            var clock = new Label(time.format("%H:%M"));
            clock.add_css_class(emphasis ? "title-2" : "title-3");
            clock.valign = Align.CENTER;
            row.append(clock);
            return row;
        }

        private void refresh() {
            clear(cities);
            var now = new DateTime.now_local();
            cities.append(city_row(_("Local Time"), now.format(_("%A %e %B")), now, true));
            string[] zones = settings != null ? settings.get_strv("world-clocks") : new string[0];
            int limit = size.h >= 2 ? 3 : 1;
            int shown = 0;
            foreach (string zone in zones) {
                if (shown == limit) break;
                TimeZone tz;
                try {
                    tz = new TimeZone.identifier(zone);
                } catch (Error e) {
                    continue;
                }
                var there = now.to_timezone(tz);
                int there_day = there.get_year() * 10000 + there.get_month() * 100 + there.get_day_of_month();
                int local_day = now.get_year() * 10000 + now.get_month() * 100 + now.get_day_of_month();
                string day = there_day > local_day ? _("Tomorrow") : (there_day < local_day ? _("Yesterday") : "");
                string detail = day != "" ? "%s, %s".printf(day, offset_text(now, there)) : offset_text(now, there);
                cities.append(city_row(city_name(zone), detail, there, false));
                shown++;
            }
            if (zones.length == 0) {
                var hint = new Label(_("Add cities in Clock"));
                hint.xalign = 0;
                hint.add_css_class("caption");
                hint.add_css_class("dim-label");
                cities.append(hint);
            } else if (zones.length > shown) {
                var more = new Label(ngettext("%d more city", "%d more cities", zones.length - shown).printf(zones.length - shown));
                more.xalign = 0;
                more.add_css_class("caption");
                more.add_css_class("dim-label");
                cities.append(more);
            }
            refresh_alarm(now);
        }

        private void refresh_alarm(DateTime now) {
            if (alarm_box == null) return;
            clear(alarm_box);
            var icon = new Image.from_icon_name("alarm-symbolic");
            icon.pixel_size = 20;
            alarm_box.append(icon);

            string? alarm_id = null;
            DateTime? when = null;
            string label = "";
            bool skipped = false;
            if (settings != null) {
                int64 skip_at = 0;
                var skips = settings.get_value("skipped-alarms");
                var iter = settings.get_value("alarms").iterator();
                string id, text;
                int hour, minute;
                uint days;
                bool enabled;
                while (iter.next("(siiusb)", out id, out hour, out minute, out days, out text, out enabled)) {
                    if (!enabled) continue;
                    var ring = Singularity.Apps.Alarm.next_occurrence(hour, minute, days, now);
                    if (when == null || ring.compare(when) < 0) {
                        when = ring;
                        alarm_id = id;
                        label = text;
                        skipped = skips.lookup(id, "x", out skip_at) && skip_at == ring.to_unix();
                    }
                }
            }

            var texts = new Box(Orientation.VERTICAL, 0);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            var click = new GestureClick();
            click.released.connect(() => open_view("alarms"));
            texts.add_controller(click);
            texts.cursor = new Gdk.Cursor.from_name("pointer", null);
            var title = new Label("");
            title.xalign = 0;
            title.add_css_class("heading");
            title.ellipsize = Pango.EllipsizeMode.END;
            var sub = new Label("");
            sub.xalign = 0;
            sub.add_css_class("caption");
            sub.add_css_class("dim-label");
            sub.ellipsize = Pango.EllipsizeMode.END;
            texts.append(title);
            texts.append(sub);
            alarm_box.append(texts);

            if (when == null) {
                title.label = _("No alarms");
                sub.label = _("Set one in Clock");
                return;
            }
            title.label = "%s  %s".printf(when.format("%a"), when.format("%H:%M"));
            string state = skipped ? _("Skipped") : _("Next alarm");
            sub.label = label != "" ? "%s, %s".printf(state, label) : state;

            var skip_box = new Box(Orientation.VERTICAL, 2);
            skip_box.valign = Align.CENTER;
            var toggle = new Switch();
            toggle.halign = Align.CENTER;
            toggle.active = skipped;
            toggle.tooltip_text = _("Skip this alarm once");
            var toggle_label = new Label(_("Skip"));
            toggle_label.add_css_class("caption");
            skip_box.append(toggle);
            skip_box.append(toggle_label);
            alarm_box.append(skip_box);
            string captured = alarm_id;
            int64 at = when.to_unix();
            toggle.notify["active"].connect(() => set_skipped(captured, at, toggle.active));
        }

        private void set_skipped(string id, int64 at, bool skip) {
            if (settings == null || updating) return;
            updating = true;
            var builder = new VariantBuilder(new VariantType("a{sx}"));
            var iter = settings.get_value("skipped-alarms").iterator();
            string key;
            int64 value;
            int64 now = get_real_time() / TimeSpan.SECOND;
            while (iter.next("{sx}", out key, out value)) {
                if (key != id && value > now) builder.add("{sx}", key, value);
            }
            if (skip) builder.add("{sx}", id, at);
            settings.set_value("skipped-alarms", builder.end());
            updating = false;
        }

        private void close_overview_later() {
            Timeout.add(600, () => {
                if (get_mapped()) Singularity.OverviewWidgetRegistry.get_default().close_overview();
                return Source.REMOVE;
            });
        }

        private void open_view(string view) {
            close_overview_later();
            var parameters = new VariantBuilder(new VariantType("av"));
            parameters.add("v", new Variant.string(view));
            var platform = new VariantBuilder(new VariantType("a{sv}"));
            Bus.get.begin(BusType.SESSION, null, (o, r) => {
                try {
                    var bus = Bus.get.end(r);
                    bus.call.begin("dev.sinty.clock", "/dev/sinty/clock", "org.freedesktop.Application", "ActivateAction",
                        new Variant("(s@av@a{sv})", "open-view", parameters.end(), platform.end()),
                        null, DBusCallFlags.NONE, 20000, null, (obj, res) => {
                            try {
                                bus.call.end(res);
                            } catch (Error e) {
                                warning("Clock widget: %s", e.message);
                            }
                        });
                } catch (Error e) {
                    warning("Clock widget: %s", e.message);
                }
            });
        }
    }

    [CCode (cname = "singularity_clock_widget_new")]
    public static Object singularity_clock_widget_new() {
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link("/proc/self/exe");
            locale_dir = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain("singularity-clock", locale_dir);
        Intl.bind_textdomain_codeset("singularity-clock", "UTF-8");
        return new WorldProvider();
    }
}

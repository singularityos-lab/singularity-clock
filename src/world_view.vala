using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class WorldView : Box {
        private unowned ClockApp app;
        private Label local_time;
        private Label local_date;
        private PreferencesGroup group;
        private Gee.ArrayList<CityRow> rows = new Gee.ArrayList<CityRow>();
        private uint refresh_id = 0;

        public WorldView(ClockApp app) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.app = app;

            var body = new Box(Orientation.VERTICAL, 20);
            body.add_css_class("clock-view");

            local_time = new Label("");
            local_time.add_css_class("clock-hero");
            local_date = new Label("");
            local_date.add_css_class("clock-hero-caption");
            body.append(local_time);
            body.append(local_date);

            group = new PreferencesGroup(_("Cities"));
            body.append(group);

            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = body;
            append(scroll);

            app.settings.changed["world-clocks"].connect(rebuild);
            rebuild();

            map.connect(() => {
                refresh();
                refresh_id = Timeout.add_seconds(1, () => {
                    refresh();
                    return Source.CONTINUE;
                });
            });
            unmap.connect(() => {
                if (refresh_id != 0) Source.remove(refresh_id);
                refresh_id = 0;
            });
        }

        public void add_city() {
            new CityDialog(app).open_dialog();
        }

        private void rebuild() {
            group.clear();
            rows.clear();
            foreach (string zone in app.settings.get_strv("world-clocks")) {
                var row = new CityRow(app, zone);
                rows.add(row);
                group.add_row(row);
            }
            group.visible = rows.size > 0;
            refresh();
        }

        private void refresh() {
            var now = new DateTime.now_local();
            local_time.label = now.format("%H:%M");
            local_date.label = now.format(_("%A %e %B"));
            foreach (var row in rows) row.refresh(now);
        }

        public static string city_name(string zone) {
            string[] parts = zone.split("/");
            return parts[parts.length - 1].replace("_", " ");
        }
    }

    public class CityRow : ActionRow {
        private unowned ClockApp app;
        private string zone;
        private TimeZone tz;
        private Label time;

        public CityRow(ClockApp app, string zone) {
            base(WorldView.city_name(zone), zone.replace("_", " "));
            this.app = app;
            this.zone = zone;
            try {
                tz = new TimeZone.identifier(zone);
            } catch (Error e) {
                tz = new TimeZone.utc();
            }

            time = new Label("");
            time.add_css_class("clock-city-time");
            time.valign = Align.CENTER;

            var remove = new Button.from_icon_name("user-trash-symbolic");
            remove.add_css_class("flat");
            remove.valign = Align.CENTER;
            remove.tooltip_text = _("Remove");
            remove.clicked.connect(() => {
                string[] kept = {};
                foreach (string item in app.settings.get_strv("world-clocks")) {
                    if (item != zone) kept += item;
                }
                app.settings.set_strv("world-clocks", kept);
            });

            add_suffix(time);
            add_suffix(remove);
        }

        public void refresh(DateTime now) {
            var there = now.to_timezone(tz);
            time.label = there.format("%H:%M");
            int64 offset_minutes = (there.get_utc_offset() - now.get_utc_offset()) / TimeSpan.MINUTE;
            int day_delta = there.get_day_of_year() - now.get_day_of_year();
            if (day_delta > 1) day_delta = -1;
            if (day_delta < -1) day_delta = 1;
            string day = day_delta == 0 ? _("Today") : (day_delta > 0 ? _("Tomorrow") : _("Yesterday"));
            string difference;
            if (offset_minutes == 0) {
                difference = _("Same time");
            } else {
                int hours = (int) (offset_minutes / 60).abs();
                int minutes = (int) (offset_minutes % 60).abs();
                string sign = offset_minutes > 0 ? "+" : "-";
                difference = minutes == 0
                    ? "%s%dh".printf(sign, hours)
                    : "%s%d:%02dh".printf(sign, hours, minutes);
            }
            subtitle = "%s  ·  %s".printf(day, difference);
        }
    }

    public class CityDialog : AppDialog {
        private unowned ClockApp app;
        private ListBox list;
        private Singularity.Widgets.SearchEntry search;

        public CityDialog(ClockApp app) {
            base(app, true);
            this.app = app;
            set_title(_("Add City"));
            set_default_size(380, 460);

            var body = new Box(Orientation.VERTICAL, 12);
            body.margin_top = 8;
            body.margin_bottom = 16;
            body.margin_start = 16;
            body.margin_end = 16;

            search = new Singularity.Widgets.SearchEntry();
            search.placeholder_text = _("Search for a city");
            body.append(search);

            list = new ListBox();
            list.add_css_class("content");
            list.selection_mode = SelectionMode.NONE;
            list.activate_on_single_click = true;
            foreach (string zone in load_zones()) {
                var label = new Label(WorldView.city_name(zone));
                label.halign = Align.START;
                label.margin_top = 8;
                label.margin_bottom = 8;
                label.margin_start = 12;
                label.tooltip_text = zone;
                var row = new ListBoxRow();
                row.child = label;
                row.set_data<string>("zone", zone);
                list.append(row);
            }
            list.set_filter_func((row) => {
                string term = search.text.strip().casefold();
                if (term == "") return true;
                return row.get_data<string>("zone").replace("_", " ").casefold().contains(term);
            });
            list.row_activated.connect((row) => {
                string zone = row.get_data<string>("zone");
                string[] zones = app.settings.get_strv("world-clocks");
                if (!(zone in zones)) {
                    zones += zone;
                    app.settings.set_strv("world-clocks", zones);
                }
                close_dialog();
            });
            search.search_changed.connect(() => list.invalidate_filter());

            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = list;
            body.append(scroll);
            content_box.append(body);
        }

        private static string[] load_zones() {
            string[] zones = {};
            foreach (string path in new string[] { "/usr/share/zoneinfo/zone1970.tab", "/usr/share/zoneinfo/zone.tab" }) {
                string contents;
                try {
                    if (!FileUtils.get_contents(path, out contents)) continue;
                } catch (FileError e) {
                    continue;
                }
                foreach (string line in contents.split("\n")) {
                    if (line.has_prefix("#") || line.strip() == "") continue;
                    string[] fields = line.split("\t");
                    if (fields.length >= 3) zones += fields[2];
                }
                break;
            }
            qsort_with_data<string>(zones, sizeof(string), (a, b) => strcmp(WorldView.city_name(a), WorldView.city_name(b)));
            return zones;
        }
    }
}

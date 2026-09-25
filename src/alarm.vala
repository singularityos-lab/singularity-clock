namespace Singularity.Apps {

    public class Alarm : Object {
        public const uint MONDAY = 1 << 0;
        public const uint WEEKDAYS = 0x1f;
        public const uint EVERY_DAY = 0x7f;

        public string id { get; construct; }
        public int hour { get; set; }
        public int minute { get; set; }
        public uint days { get; set; }
        public string label { get; set; default = ""; }
        public bool enabled { get; set; default = true; }

        public Alarm(string id, int hour, int minute, uint days, string label, bool enabled) {
            Object(id: id, hour: hour, minute: minute, days: days, label: label, enabled: enabled);
        }

        public string time_text() {
            return "%02d:%02d".printf(hour, minute);
        }

        public string days_text() {
            if (days == 0) return _("Once");
            if (days == EVERY_DAY) return _("Every day");
            if (days == WEEKDAYS) return _("Weekdays");
            if (days == (EVERY_DAY & ~WEEKDAYS)) return _("Weekends");
            string[] names = { _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat"), _("Sun") };
            string[] picked = {};
            for (int i = 0; i < 7; i++) {
                if ((days & (MONDAY << i)) != 0) picked += names[i];
            }
            return string.joinv(", ", picked);
        }

        public DateTime next_ring(DateTime after) {
            return next_occurrence(hour, minute, days, after);
        }

        public static DateTime next_occurrence(int hour, int minute, uint days, DateTime after) {
            var day = new DateTime.local(after.get_year(), after.get_month(), after.get_day_of_month(), 0, 0, 0);
            for (int offset = 0; offset < 8; offset++) {
                var date = day.add_days(offset);
                var candidate = new DateTime.local(date.get_year(), date.get_month(), date.get_day_of_month(),
                                                   hour, minute, 0);
                if (candidate.compare(after) <= 0) continue;
                if (days == 0 || (days & (MONDAY << (candidate.get_day_of_week() - 1))) != 0) {
                    return candidate;
                }
            }
            return day.add_days(8);
        }
    }
}

namespace Singularity.Apps {

    public class AlarmStore : Object {
        private GLib.Settings settings;
        private Gee.ArrayList<Alarm> _alarms = new Gee.ArrayList<Alarm>();
        private Gee.HashMap<string, DateTime> snoozed = new Gee.HashMap<string, DateTime>();
        private DateTime last_check;
        private uint tick_id = 0;
        private bool saving = false;

        public signal void changed();
        public signal void ringing(Alarm alarm);

        public Gee.List<Alarm> alarms {
            owned get { return _alarms.read_only_view; }
        }

        public AlarmStore(GLib.Settings settings) {
            this.settings = settings;
            last_check = new DateTime.now_local();
            load();
            settings.changed["alarms"].connect(() => {
                if (saving) return;
                load();
                changed();
                schedule();
            });
            schedule();
        }

        public bool any_enabled() {
            foreach (var alarm in _alarms) {
                if (alarm.enabled) return true;
            }
            return snoozed.size > 0;
        }

        public Alarm? find(string id) {
            foreach (var alarm in _alarms) {
                if (alarm.id == id) return alarm;
            }
            return null;
        }

        public void add(int hour, int minute, uint days, string label) {
            _alarms.add(new Alarm(Uuid.string_random(), hour, minute, days, label, true));
            commit();
        }

        public void update(Alarm alarm) {
            snoozed.unset(alarm.id);
            commit();
        }

        public void remove(string id) {
            var alarm = find(id);
            if (alarm == null) return;
            _alarms.remove(alarm);
            snoozed.unset(id);
            commit();
        }

        public void snooze(string id, int minutes) {
            snoozed[id] = new DateTime.now_local().add_minutes(minutes);
            changed();
            schedule();
        }

        private void load() {
            _alarms.clear();
            var iter = settings.get_value("alarms").iterator();
            string id, label;
            int hour, minute;
            uint days;
            bool enabled;
            while (iter.next("(siiusb)", out id, out hour, out minute, out days, out label, out enabled)) {
                _alarms.add(new Alarm(id, hour, minute, days, label, enabled));
            }
            _alarms.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
        }

        private void commit() {
            _alarms.sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
            var builder = new VariantBuilder(new VariantType("a(siiusb)"));
            foreach (var alarm in _alarms) {
                builder.add("(siiusb)", alarm.id, alarm.hour, alarm.minute, alarm.days, alarm.label, alarm.enabled);
            }
            saving = true;
            settings.set_value("alarms", builder.end());
            saving = false;
            changed();
            schedule();
        }

        private void schedule() {
            if (tick_id != 0) {
                Source.remove(tick_id);
                tick_id = 0;
            }
            if (!any_enabled()) return;
            var now = new DateTime.now_local();
            TimeSpan wait = TimeSpan.HOUR;
            foreach (var alarm in _alarms) {
                if (alarm.enabled) wait = int64.min(wait, alarm.next_ring(now).difference(now));
            }
            foreach (var due in snoozed.values) {
                wait = int64.min(wait, due.difference(now));
            }
            uint seconds = (uint) (wait / TimeSpan.SECOND).clamp(1, 30);
            tick_id = Timeout.add_seconds(seconds, () => {
                tick_id = 0;
                tick();
                return Source.REMOVE;
            });
        }

        private void tick() {
            var now = new DateTime.now_local();
            bool disabled_once = false;
            foreach (var alarm in _alarms.to_array()) {
                if (!alarm.enabled || alarm.next_ring(last_check).compare(now) > 0) continue;
                if (alarm.days == 0) {
                    alarm.enabled = false;
                    disabled_once = true;
                }
                ringing(alarm);
            }
            foreach (var id in snoozed.keys.to_array()) {
                if (snoozed[id].compare(now) > 0) continue;
                snoozed.unset(id);
                var alarm = find(id);
                if (alarm != null) ringing(alarm);
            }
            last_check = now;
            if (disabled_once) commit();
            else schedule();
        }
    }
}

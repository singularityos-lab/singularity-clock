namespace Singularity.Apps {

    public struct TimerEntry {
        public string id;
        public string kind;
        public string state;
        public int64 end_time;
        public int64 remaining;
        public int64 duration;
    }

    [DBus (name = "dev.sinty.Clock.Timers")]
    public class TimerService : Object {
        public const string MAIN_ID = "main";
        private unowned ClockApp app;

        public signal void changed(string id, string kind, string state, int64 end_time, int64 remaining, int64 duration);
        public signal void finished(string id, string kind);

        public uint version {
            get { return 1; }
        }

        public TimerService(ClockApp app) {
            this.app = app;
        }

        [DBus (visible = false)]
        public TimerEntry entry() {
            var t = app.timer;
            TimerEntry e = TimerEntry();
            e.id = MAIN_ID;
            e.kind = t.kind.to_id();
            e.state = t.paused ? "paused" : (t.running ? "running" : "idle");
            e.remaining = t.remaining_usec();
            e.end_time = t.running && !t.paused ? get_real_time() + e.remaining : 0;
            e.duration = t.duration;
            return e;
        }

        [DBus (visible = false)]
        public void emit_changed() {
            var e = entry();
            changed(e.id, e.kind, e.state, e.end_time, e.remaining, e.duration);
        }

        public TimerEntry[] list_timers() throws Error {
            var e = entry();
            if (e.state == "idle") return {};
            return { e };
        }

        public string start(int seconds) throws Error {
            if (seconds <= 0 || seconds > 24 * 3600) throw new DBusError.INVALID_ARGS("seconds out of range");
            app.start_timer(seconds);
            return MAIN_ID;
        }

        public string start_pomodoro() throws Error {
            app.start_pomodoro();
            return MAIN_ID;
        }

        private void check(string id) throws Error {
            if (id != MAIN_ID) throw new DBusError.INVALID_ARGS("unknown timer %s", id);
        }

        public void pause(string id) throws Error {
            check(id);
            app.timer.pause();
        }

        public void resume(string id) throws Error {
            check(id);
            app.timer.resume();
        }

        public void cancel(string id) throws Error {
            check(id);
            app.cancel_timer();
        }
    }
}

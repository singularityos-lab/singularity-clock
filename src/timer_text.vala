namespace Singularity.Apps {

    public enum TimerKind {
        TIMER,
        FOCUS,
        SHORT_BREAK,
        LONG_BREAK;

        public string to_id() {
            switch (this) {
                case FOCUS: return "focus";
                case SHORT_BREAK: return "short-break";
                case LONG_BREAK: return "long-break";
                default: return "timer";
            }
        }

        public static TimerKind from_id(string id) {
            switch (id) {
                case "focus": return FOCUS;
                case "short-break": return SHORT_BREAK;
                case "long-break": return LONG_BREAK;
                default: return TIMER;
            }
        }

        public bool is_pomodoro() {
            return this != TIMER;
        }

        public bool is_break() {
            return this == SHORT_BREAK || this == LONG_BREAK;
        }
    }

    namespace TimerText {
        public int64 whole_seconds(int64 usec) {
            if (usec <= 0) return 0;
            return (usec + TimeSpan.SECOND - 1) / TimeSpan.SECOND;
        }

        public string countdown(int64 usec) {
            int64 total = whole_seconds(usec);
            int64 hours = total / 3600;
            int64 minutes = (total / 60) % 60;
            int64 seconds = total % 60;
            if (hours > 0) return "%lld:%02lld:%02lld".printf(hours, minutes, seconds);
            return "%02lld:%02lld".printf(minutes, seconds);
        }

        public string compact(int64 usec) {
            int64 total = whole_seconds(usec);
            int64 hours = total / 3600;
            int64 minutes = (total / 60) % 60;
            int64 seconds = total % 60;
            if (hours > 0) return "%lld:%02lld:%02lld".printf(hours, minutes, seconds);
            return "%lld:%02lld".printf(minutes, seconds);
        }

        public int64 remaining(string state, int64 end_time, int64 remaining, int64 now) {
            if (state == "running") return int64.max(0, end_time - now);
            if (state == "paused") return int64.max(0, remaining);
            return 0;
        }

        public double fraction(int64 left, int64 duration) {
            if (duration <= 0) return 0.0;
            return ((double) left / duration).clamp(0.0, 1.0);
        }
    }

    public class PomodoroCycle : Object {
        public int focus_minutes { get; set; default = 25; }
        public int short_break_minutes { get; set; default = 5; }
        public int long_break_minutes { get; set; default = 15; }
        public int rounds_before_long_break { get; set; default = 4; }
        public int completed { get; private set; default = 0; }

        public int minutes_for(TimerKind kind) {
            switch (kind) {
                case TimerKind.FOCUS: return focus_minutes;
                case TimerKind.SHORT_BREAK: return short_break_minutes;
                case TimerKind.LONG_BREAK: return long_break_minutes;
                default: return 0;
            }
        }

        public bool next_after(TimerKind finished, out TimerKind next) {
            next = TimerKind.TIMER;
            if (finished != TimerKind.FOCUS) return false;
            completed++;
            int every = int.max(1, rounds_before_long_break);
            next = completed % every == 0 ? TimerKind.LONG_BREAK : TimerKind.SHORT_BREAK;
            return true;
        }

        public void reset() {
            completed = 0;
        }
    }
}

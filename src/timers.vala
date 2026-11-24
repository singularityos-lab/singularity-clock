namespace Singularity.Apps {

    public class CountdownTimer : Object {
        private int64 end_time = 0;
        private int64 paused_remaining = 0;
        private uint tick_id = 0;

        public int64 duration { get; private set; default = 0; }
        public TimerKind kind { get; private set; default = TimerKind.TIMER; }
        public bool running { get; private set; default = false; }
        public bool paused { get; private set; default = false; }

        public signal void tick();
        public signal void finished();

        public int64 remaining_usec() {
            if (paused) return paused_remaining;
            if (!running) return 0;
            return int64.max(0, end_time - get_real_time());
        }

        public void start(int64 seconds, TimerKind kind = TimerKind.TIMER) {
            this.kind = kind;
            duration = seconds * TimeSpan.SECOND;
            end_time = get_real_time() + duration;
            running = true;
            paused = false;
            arm();
        }

        public Variant save_state() {
            return new Variant("(sbbxxx)", kind.to_id(), running, paused, end_time, paused_remaining, duration);
        }

        public void restore_state(Variant state) {
            string id;
            bool was_running, was_paused;
            int64 end, rest, length;
            state.get("(sbbxxx)", out id, out was_running, out was_paused, out end, out rest, out length);
            disarm();
            kind = TimerKind.from_id(id);
            duration = length;
            end_time = end;
            paused_remaining = rest;
            paused = was_paused;
            running = was_running;
            if (running && !paused) arm();
            tick();
        }

        public void pause() {
            if (!running || paused) return;
            paused_remaining = remaining_usec();
            paused = true;
            disarm();
            tick();
        }

        public void resume() {
            if (!paused) return;
            end_time = get_real_time() + paused_remaining;
            paused = false;
            arm();
        }

        public void cancel() {
            running = false;
            paused = false;
            disarm();
            tick();
        }

        private void arm() {
            disarm();
            tick_id = Timeout.add(200, () => {
                if (remaining_usec() > 0) {
                    tick();
                    return Source.CONTINUE;
                }
                tick_id = 0;
                running = false;
                tick();
                finished();
                return Source.REMOVE;
            });
        }

        private void disarm() {
            if (tick_id != 0) {
                Source.remove(tick_id);
                tick_id = 0;
            }
        }
    }

    public class Stopwatch : Object {
        private int64 started_at = 0;
        private int64 started_real = 0;
        private int64 accumulated = 0;
        private int64 last_lap = 0;
        private uint tick_id = 0;

        public bool running { get; private set; default = false; }
        public Gee.ArrayList<int64?> laps { get; private set; default = new Gee.ArrayList<int64?>(); }

        public signal void tick();
        public signal void laps_changed();

        public int64 elapsed_usec() {
            return accumulated + (running ? get_monotonic_time() - started_at : 0);
        }

        public void start() {
            if (running) return;
            started_at = get_monotonic_time();
            started_real = get_real_time();
            running = true;
            arm();
        }

        private void arm() {
            tick_id = Timeout.add(40, () => {
                tick();
                return Source.CONTINUE;
            });
        }

        public Variant save_state() {
            var marks = new VariantBuilder(new VariantType("ax"));
            foreach (int64? lap in laps) marks.add("x", (int64) lap);
            return new Variant("(bxxx@ax)", running, running ? started_real : 0, accumulated, last_lap, marks.end());
        }

        public void restore_state(Variant state) {
            bool was_running;
            int64 real, total, previous;
            Variant marks;
            state.get("(bxxx@ax)", out was_running, out real, out total, out previous, out marks);
            if (tick_id != 0) Source.remove(tick_id);
            tick_id = 0;
            accumulated = total;
            last_lap = previous;
            laps.clear();
            foreach (var lap in marks) laps.add(lap.get_int64());
            if (was_running) {
                started_real = real;
                started_at = get_monotonic_time() - (get_real_time() - real);
                arm();
            }
            running = was_running;
            laps_changed();
            tick();
        }

        public void stop() {
            if (!running) return;
            accumulated = elapsed_usec();
            running = false;
            Source.remove(tick_id);
            tick_id = 0;
            tick();
        }

        public void lap() {
            int64 now = elapsed_usec();
            laps.insert(0, now - last_lap);
            last_lap = now;
            laps_changed();
        }

        public void reset() {
            stop();
            accumulated = 0;
            last_lap = 0;
            laps.clear();
            laps_changed();
            tick();
        }

        public static string format(int64 usec, bool centiseconds) {
            int64 total_cs = usec / 10000;
            int hours = (int) (total_cs / 360000);
            int minutes = (int) ((total_cs / 6000) % 60);
            int seconds = (int) ((total_cs / 100) % 60);
            string text = hours > 0
                ? "%d:%02d:%02d".printf(hours, minutes, seconds)
                : "%02d:%02d".printf(minutes, seconds);
            return centiseconds ? text + ".%02d".printf((int) (total_cs % 100)) : text;
        }
    }
}

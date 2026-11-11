namespace Singularity.Apps {

    internal class ClockIntents : Object {
        private const string[] DAY_IDS = { "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" };

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static Json.Node done(Json.Builder b) {
            b.end_object();
            return b.get_root();
        }

        private static void parse_time(string value, out int hour, out int minute) throws Error {
            hour = 0;
            minute = 0;
            string clean = value.strip();
            MatchInfo m;
            if (!/^([0-9]{1,2})(?:[:.]([0-9]{2}))?\s*(am|pm)?$/i.match(clean, 0, out m)) {
                throw new IOError.INVALID_ARGUMENT("give the time as HH:MM");
            }
            hour = int.parse(m.fetch(1));
            string? mm = m.fetch(2);
            minute = mm != null && mm != "" ? int.parse(mm) : 0;
            string half = m.fetch(3) != null ? m.fetch(3).down() : "";
            if (half == "pm" && hour < 12) hour += 12;
            if (half == "am" && hour == 12) hour = 0;
            if (hour > 23 || minute > 59) throw new IOError.INVALID_ARGUMENT("%s is not a time of day", value);
        }

        private static uint parse_days(Json.Object args) throws Error {
            if (!args.has_member("days")) return 0;
            var node = args.get_member("days");
            string[] words = {};
            if (node.get_node_type() == Json.NodeType.ARRAY) {
                foreach (var e in node.get_array().get_elements()) words += e.get_string().strip().down();
            } else {
                words = { node.get_string().strip().down() };
            }
            uint days = 0;
            foreach (string w in words) {
                switch (w) {
                    case "":
                    case "once":
                        break;
                    case "weekdays":
                        days |= Alarm.WEEKDAYS;
                        break;
                    case "weekends":
                        days |= Alarm.EVERY_DAY & ~Alarm.WEEKDAYS;
                        break;
                    case "every day":
                    case "everyday":
                    case "daily":
                        days |= Alarm.EVERY_DAY;
                        break;
                    default:
                        bool found = false;
                        for (int i = 0; i < 7; i++) {
                            if (DAY_IDS[i] == w || DAY_IDS[i].substring(0, 3) == w) {
                                days |= Alarm.MONDAY << i;
                                found = true;
                            }
                        }
                        if (!found) throw new IOError.INVALID_ARGUMENT("%s is not a day", w);
                        break;
                }
            }
            return days;
        }

        private static string[] day_names(uint days) {
            string[] names = {};
            for (int i = 0; i < 7; i++) if ((days & (Alarm.MONDAY << i)) != 0) names += DAY_IDS[i];
            return names;
        }

        private static void alarm_members(Json.Builder b, Alarm alarm, AlarmStore store) {
            var next = alarm.next_ring(new DateTime.now_local());
            b.set_member_name("id").add_string_value(alarm.id);
            b.set_member_name("time").add_string_value(alarm.time_text());
            b.set_member_name("label").add_string_value(alarm.label);
            b.set_member_name("enabled").add_boolean_value(alarm.enabled);
            b.set_member_name("days").begin_array();
            foreach (string d in day_names(alarm.days)) b.add_string_value(d);
            b.end_array();
            b.set_member_name("repeats").add_string_value(alarm.days_text());
            if (alarm.enabled) {
                b.set_member_name("next").add_string_value(next.format_iso8601());
                b.set_member_name("next_skipped").add_boolean_value(store.is_skipped(alarm, next));
            }
        }

        private static Alarm find(ClockApp app, Json.Object args) throws Error {
            string id = text(args, "id");
            Alarm? alarm = id != "" ? app.alarms.find(id) : null;
            if (alarm == null && id != "") {
                foreach (var a in app.alarms.alarms) {
                    if (a.time_text() == id || (a.label != "" && a.label.casefold() == id.casefold())) {
                        if (alarm != null) throw new IOError.INVALID_ARGUMENT("more than one alarm matches %s: use its id", id);
                        alarm = a;
                    }
                }
            }
            if (alarm == null) throw new IOError.NOT_FOUND("no alarm %s; list them with clock_alarms", id);
            return alarm;
        }

        private static Json.Node timer_state(ClockApp app) {
            var t = app.timer;
            var b = new Json.Builder();
            b.begin_object();
            string state = t.paused ? "paused" : (t.running ? "running" : "idle");
            b.set_member_name("state").add_string_value(state);
            b.set_member_name("kind").add_string_value(t.kind.to_id());
            if (state != "idle") {
                b.set_member_name("remaining_seconds").add_int_value(t.remaining_usec() / 1000000);
                b.set_member_name("duration_seconds").add_int_value(t.duration / 1000000);
            }
            b.set_member_name("stopwatch").begin_object();
            b.set_member_name("running").add_boolean_value(app.stopwatch.running);
            b.set_member_name("elapsed").add_string_value(Stopwatch.format(app.stopwatch.elapsed_usec(), true));
            b.set_member_name("laps").add_int_value(app.stopwatch.laps.size);
            b.end_object();
            return done(b);
        }

        private static string zone_time(string zone) throws Error {
            var tz = new TimeZone.identifier(zone);
            if (tz == null) throw new IOError.NOT_FOUND("unknown time zone %s", zone);
            return new DateTime.now(tz).format("%Y-%m-%dT%H:%M:%S%:z");
        }

        private static string find_zone(string query) throws Error {
            string want = query.strip().replace(" ", "_").casefold();
            if (want == "") throw new IOError.INVALID_ARGUMENT("give a city or a time zone");
            if ("/" in query) {
                var tz = new TimeZone.identifier(query.strip());
                if (tz != null) return tz.get_identifier();
            }
            const string ROOT = "/usr/share/zoneinfo";
            string? best = null;
            string[] stack = { ROOT };
            while (stack.length > 0) {
                string current = stack[stack.length - 1];
                stack.resize(stack.length - 1);
                Dir dir;
                try {
                    dir = Dir.open(current);
                } catch (Error e) {
                    continue;
                }
                string? name;
                while ((name = dir.read_name()) != null) {
                    if (name == "posix" || name == "right") continue;
                    string path = Path.build_filename(current, name);
                    if (FileUtils.test(path, FileTest.IS_DIR)) {
                        stack += path;
                        continue;
                    }
                    if (name.casefold() == want) {
                        string id = path.substring(ROOT.length + 1);
                        if (best == null || id.length < best.length) best = id;
                    }
                }
            }
            if (best == null) throw new IOError.NOT_FOUND("no time zone for %s", query);
            return best;
        }

        internal static void install(ClockApp app) {
            var agent = app.agent;
            agent.add_intent("clock_alarms", "List the alarms with their time, repeat days, label, whether they are on and when each rings next.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_array();
                    foreach (var alarm in app.alarms.alarms) {
                        b.begin_object();
                        alarm_members(b, alarm, app.alarms);
                        b.end_object();
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_intent("clock_add_alarm", "Add an alarm at a time of day (HH:MM, 24 hours or with am/pm). days is once (default), weekdays, weekends, every day, or a list of weekday names.",
                "{\"type\":\"object\",\"properties\":{\"time\":{\"type\":\"string\"},\"days\":{\"type\":[\"string\",\"array\"],\"items\":{\"type\":\"string\"}},\"label\":{\"type\":\"string\"}},\"required\":[\"time\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    int hour, minute;
                    parse_time(text(args, "time"), out hour, out minute);
                    uint days = parse_days(args);
                    var before = new Gee.HashSet<string>();
                    foreach (var a in app.alarms.alarms) before.add(a.id);
                    app.alarms.add(hour, minute, days, text(args, "label"));
                    Alarm? added = null;
                    foreach (var a in app.alarms.alarms) if (!before.contains(a.id)) added = a;
                    if (added == null) throw new IOError.FAILED("the alarm was not saved");
                    var b = new Json.Builder();
                    b.begin_object();
                    alarm_members(b, added, app.alarms);
                    b.set_member_name("undo").add_string_value("clock_remove_alarm with id " + added.id);
                    return done(b);
                });
            agent.add_intent("clock_set_alarm", "Change an alarm found by id, time or label: turn it on or off, skip or unskip its next ring, or move its time, days or label.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"enabled\":{\"type\":\"boolean\"},\"skip_next\":{\"type\":\"boolean\"},\"time\":{\"type\":\"string\"},\"days\":{\"type\":[\"string\",\"array\"],\"items\":{\"type\":\"string\"}},\"label\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var alarm = find(app, args);
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("before").begin_object();
                    alarm_members(b, alarm, app.alarms);
                    b.end_object();
                    if (args.has_member("time")) {
                        int hour, minute;
                        parse_time(text(args, "time"), out hour, out minute);
                        alarm.hour = hour;
                        alarm.minute = minute;
                    }
                    if (args.has_member("days")) alarm.days = parse_days(args);
                    if (args.has_member("label")) alarm.label = text(args, "label");
                    if (args.has_member("enabled")) alarm.enabled = args.get_boolean_member("enabled");
                    app.alarms.update(alarm);
                    if (args.has_member("skip_next")) app.alarms.set_skipped(alarm, args.get_boolean_member("skip_next"));
                    var now = app.alarms.find(alarm.id);
                    if (now == null) throw new IOError.FAILED("the alarm disappeared");
                    b.set_member_name("after").begin_object();
                    alarm_members(b, now, app.alarms);
                    b.end_object();
                    return done(b);
                });
            agent.add_intent("clock_remove_alarm", "Delete an alarm found by id, time or label.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var alarm = find(app, args);
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("removed").begin_object();
                    alarm_members(b, alarm, app.alarms);
                    b.end_object();
                    b.set_member_name("undo").add_string_value("clock_add_alarm with time %s, days [%s], label \"%s\"".printf(
                        alarm.time_text(), string.joinv(", ", day_names(alarm.days)), alarm.label));
                    string id = alarm.id;
                    app.alarms.remove(id);
                    if (app.alarms.find(id) != null) throw new IOError.FAILED("the alarm is still there");
                    return done(b);
                });
            agent.add_intent("clock_timer", "The countdown timer and stopwatch state.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    return timer_state(app);
                });
            agent.add_intent("clock_start_timer", "Start the countdown timer for hours, minutes and seconds added together, or a focus session when pomodoro is true. It replaces a running timer.",
                "{\"type\":\"object\",\"properties\":{\"hours\":{\"type\":\"integer\"},\"minutes\":{\"type\":\"integer\"},\"seconds\":{\"type\":\"integer\"},\"pomodoro\":{\"type\":\"boolean\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    if (args.has_member("pomodoro") && args.get_boolean_member("pomodoro")) {
                        app.start_pomodoro();
                    } else {
                        int64 total = (args.has_member("hours") ? args.get_int_member("hours") * 3600 : 0)
                            + (args.has_member("minutes") ? args.get_int_member("minutes") * 60 : 0)
                            + (args.has_member("seconds") ? args.get_int_member("seconds") : 0);
                        if (total <= 0 || total > 24 * 3600) throw new IOError.INVALID_ARGUMENT("the timer must be between 1 second and 24 hours");
                        app.start_timer((int) total);
                    }
                    if (!app.timer.running) throw new IOError.FAILED("the timer did not start");
                    return timer_state(app);
                });
            agent.add_intent("clock_timer_control", "Pause, resume or cancel the countdown timer, or start, stop, lap or reset the stopwatch.",
                "{\"type\":\"object\",\"properties\":{\"action\":{\"type\":\"string\",\"enum\":[\"pause\",\"resume\",\"cancel\",\"stopwatch_start\",\"stopwatch_stop\",\"stopwatch_lap\",\"stopwatch_reset\"]}},\"required\":[\"action\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    switch (text(args, "action")) {
                        case "pause": app.timer.pause(); break;
                        case "resume": app.timer.resume(); break;
                        case "cancel": app.cancel_timer(); break;
                        case "stopwatch_start": app.stopwatch.start(); break;
                        case "stopwatch_stop": app.stopwatch.stop(); break;
                        case "stopwatch_lap": app.stopwatch.lap(); break;
                        case "stopwatch_reset": app.stopwatch.reset(); break;
                        default: throw new IOError.INVALID_ARGUMENT("unknown action");
                    }
                    return timer_state(app);
                });
            agent.add_intent("clock_world", "The world clocks saved in Clock with the time there now, or the time now in any city or time zone when place is given.",
                "{\"type\":\"object\",\"properties\":{\"place\":{\"type\":\"string\"}}}", Singularity.AppIntentRisk.READ, (args) => {
                    string[] zones = text(args, "place") != "" ? new string[] { find_zone(text(args, "place")) } : app.settings.get_strv("world-clocks");
                    var b = new Json.Builder();
                    b.begin_array();
                    foreach (string zone in zones) {
                        b.begin_object();
                        b.set_member_name("zone").add_string_value(zone);
                        b.set_member_name("time").add_string_value(zone_time(zone));
                        b.end_object();
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_intent("clock_add_world", "Add a world clock for a city or time zone.",
                "{\"type\":\"object\",\"properties\":{\"place\":{\"type\":\"string\"}},\"required\":[\"place\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string zone = find_zone(text(args, "place"));
                    string[] zones = app.settings.get_strv("world-clocks");
                    if (!(zone in zones)) {
                        zones += zone;
                        app.settings.set_strv("world-clocks", zones);
                    }
                    if (!(zone in app.settings.get_strv("world-clocks"))) throw new IOError.FAILED("the clock was not saved");
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("zone").add_string_value(zone);
                    b.set_member_name("time").add_string_value(zone_time(zone));
                    return done(b);
                });
        }
    }
}

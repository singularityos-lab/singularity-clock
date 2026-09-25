namespace Singularity.Apps {

    public class Ringer : Object {
        private const string NOTIFICATION_ID = "ringing";
        private const string[] SOUNDS = {
            "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
            "/usr/share/sounds/freedesktop/stereo/complete.oga"
        };

        private unowned GLib.Application app;
        private Gtk.MediaFile? media = null;
        private Subprocess? player = null;
        private uint stop_id = 0;
        private bool active = false;

        public string? ringing_id { get; private set; default = null; }

        public Ringer(GLib.Application app) {
            this.app = app;
        }

        public void ring(string id, string title, string body, bool snoozable, int max_minutes) {
            stop();
            active = true;
            ringing_id = id;
            play();

            var notification = new Notification(title);
            notification.set_body(body);
            notification.set_priority(NotificationPriority.URGENT);
            notification.set_icon(new ThemedIcon("dev.sinty.clock"));
            notification.set_default_action("app.show");
            notification.add_button_with_target_value(_("Stop"), "app.stop-ringing", new Variant.string(id));
            if (snoozable) {
                notification.add_button_with_target_value(_("Snooze"), "app.snooze", new Variant.string(id));
            }
            app.send_notification(NOTIFICATION_ID, notification);

            stop_id = Timeout.add_seconds((uint) max_minutes * 60, () => {
                stop_id = 0;
                stop();
                return Source.REMOVE;
            });
        }

        public void stop() {
            active = false;
            ringing_id = null;
            if (stop_id != 0) {
                Source.remove(stop_id);
                stop_id = 0;
            }
            if (media != null) {
                media.playing = false;
                media = null;
            }
            if (player != null) {
                player.force_exit();
                player = null;
            }
            app.withdraw_notification(NOTIFICATION_ID);
        }

        private string? sound_path() {
            foreach (unowned string path in SOUNDS) {
                if (FileUtils.test(path, FileTest.EXISTS)) return path;
            }
            return null;
        }

        private void play() {
            string? path = sound_path();
            if (path == null) return;
            media = Gtk.MediaFile.for_filename(path);
            media.loop = true;
            media.notify["error"].connect(() => {
                if (media != null && media.error != null) {
                    media = null;
                    play_with_command(path);
                }
            });
            media.play();
        }

        private void play_with_command(string path) {
            if (!active) return;
            string? program = Environment.find_program_in_path("pw-play") ?? Environment.find_program_in_path("paplay");
            if (program == null) return;
            try {
                player = new Subprocess.newv({ program, path }, SubprocessFlags.NONE);
                player.wait_async.begin(null, () => {
                    player = null;
                    play_with_command(path);
                });
            } catch (Error e) {
                warning("Clock: cannot play the alarm sound: %s", e.message);
            }
        }
    }
}

using Gtk;

namespace Singularity.Apps {

    [GtkTemplate(ui = "/dev/sinty/clock/ui/main.ui")]
    public class ClockWindow : Singularity.Widgets.Window {

        [GtkChild] unowned Box   main_box;
        [GtkChild] unowned Stack view_stack;

        private AlarmsView alarms_view;
        private WorldView world_view;
        private Button add_button;

        public ClockWindow(ClockApp app) {
            Object(application: app);
            set_title(_("Clock"));
            set_default_size(460, 620);

            alarms_view = new AlarmsView(app);
            world_view = new WorldView(app);
            view_stack.add_titled(alarms_view, "alarms", _("Alarms"));
            view_stack.add_titled(world_view, "world", _("World"));
            view_stack.add_titled(new StopwatchView(app), "stopwatch", _("Stopwatch"));
            view_stack.add_titled(new TimerView(app), "timer", _("Timer"));

            add_bubble_widget(new Singularity.Widgets.BubbleSwitcher(view_stack));

            add_button = add_bubble_icon("list-add-symbolic", _("Add"), () => {
                if (view_stack.visible_child_name == "alarms") alarms_view.add_alarm();
                else world_view.add_city();
            });

            string last = app.settings.get_string("last-view");
            if (view_stack.get_child_by_name(last) != null) {
                view_stack.visible_child_name = last;
            }
            view_stack.notify["visible-child-name"].connect(() => {
                app.settings.set_string("last-view", view_stack.visible_child_name);
                update_add_button();
            });
            update_add_button();

            Singularity.Widgets.apply_view_edge(view_stack);
            set_content(main_box);
        }

        private void update_add_button() {
            string page = view_stack.visible_child_name;
            add_button.visible = page == "alarms" || page == "world";
        }
    }
}

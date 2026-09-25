project('singularity-clock', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-clock"', language: 'c')
subdir('po')

gnome = import('gnome')

gtk_dep            = dependency('gtk4')
gee_dep            = dependency('gee-0.8')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-clock-resources',
  'resources/dev.sinty.clock.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: main_ui
)

executable('singularity-clock',
  [
    'src/main.vala',
    'src/window.vala',
    'src/alarm.vala',
    'src/alarm_store.vala',
    'src/ringer.vala',
    'src/timers.vala',
    'src/alarms_view.vala',
    'src/world_view.vala',
    'src/stopwatch_view.vala',
    'src/timer_view.vala',
    resources,
  ],
  dependencies: [gtk_dep, gee_dep, libsingularity_dep],
  install: true
)

alarm_test = executable('alarm-test',
  ['tests/alarm_test.vala', 'src/alarm.vala'],
  dependencies: [gtk_dep, gee_dep],
)
test('alarm', alarm_test)

install_data('data/dev.sinty.clock.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.clock.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.clock.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.clock.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

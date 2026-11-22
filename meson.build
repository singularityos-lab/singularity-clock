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
    'src/timer_text.vala',
    'src/timer_service.vala',
    'src/alarms_view.vala',
    'src/world_view.vala',
    'src/agent_intents.vala',
    'src/stopwatch_view.vala',
    'src/timer_view.vala',
    'src/dock_status.vala',
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

timers_test = executable('timers-test',
  ['tests/timers_test.vala', 'src/timer_text.vala'],
  dependencies: [dependency('glib-2.0'), dependency('gobject-2.0')],
)
test('timers', timers_test)

shared_module('singularity-clock-widget',
  files('widget/world_widget.vala', 'src/alarm.vala'),
  dependencies: [gtk_dep, gee_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.clock.world.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

shared_module('clock-timer-tile',
  files('plugin/timer_tile.vala', 'src/timer_text.vala'),
  dependencies: [gtk_dep, libsingularity_dep, dependency('libpeas-2')],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'clock-timer-tile'
)
install_data('plugin/clock-timer-tile.plugin',
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'clock-timer-tile'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.clock.service.in',
  output: 'dev.sinty.clock.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

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

iride = find_program('iride', required: get_option('iride'))
if iride.found()
  custom_target('iride-icon',
    input: 'data/icons/iride/iride.json',
    output: 'dev.sinty.clock.iride',
    depend_files: files(
      'data/icons/iride/layers/000.svg',
      'data/icons/iride/layers/001.svg',
      'data/icons/iride/layers/002.svg',
      'data/icons/iride/layers/003.svg',
      'data/icons/iride/layers/004.svg',
      'data/icons/iride/layers/005.svg',
      'data/icons/iride/layers/006.svg',
      'data/icons/iride/layers/007.svg',
      'data/icons/iride/layers/008.svg',
      'data/icons/iride/layers/009.svg',
      'data/icons/iride/layers/010.svg',
      'data/icons/iride/layers/011.svg',
      'data/icons/iride/layers/012.svg',
      'data/icons/iride/layers/013.svg',
      'data/icons/iride/layers/014.svg',
      'data/icons/iride/layers/015.svg',
      'data/icons/iride/layers/016.svg',
      'data/icons/iride/layers/017.svg',
      'data/icons/iride/layers/018.svg',
      'data/icons/iride/layers/019.svg',
      'data/icons/iride/layers/020.svg',
      'data/icons/iride/layers/021.svg',
      'data/icons/iride/layers/022.svg',
      'data/icons/iride/layers/023.svg',
      'data/icons/iride/layers/024.svg',
      'data/icons/iride/layers/025.svg',
      'data/icons/iride/layers/026.svg',
    ),
    command: [iride, 'build', meson.current_source_dir() / 'data' / 'icons' / 'iride', '@OUTPUT@'],
    install: true,
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
  )
endif

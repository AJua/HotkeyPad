import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
// Flutter's own ConnectionState (used by StreamBuilder) collides with the BLE one.
import 'package:flutter/material.dart' hide ConnectionState;

import 'app_launcher.dart';
import 'command_runner.dart';
import 'layout_page.dart';
import 'layout_store.dart';
import 'media_control.dart';
import 'protocol.dart';
import 'settings_store.dart';
import 'unsupported_page.dart';

/// A client that the host has seen. Centrals are only reported to us when
/// they do something — connect, subscribe, read or write — so the list grows
/// as clients interact rather than the moment they come into range.
class ConnectedClient {
  ConnectedClient({
    required this.central,
    required this.since,
    required this.subscribed,
    required this.lastActivity,
  });

  final Central central;
  final DateTime since;
  final bool subscribed;
  final String lastActivity;

  String get id => central.uuid.toString();

  ConnectedClient copyWith({bool? subscribed, String? lastActivity}) {
    return ConnectedClient(
      central: central,
      since: since,
      subscribed: subscribed ?? this.subscribed,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}

class HostPage extends StatefulWidget {
  const HostPage({super.key, required this.onThemeChanged});

  /// Lets the app above re-dress itself when the theme is changed here.
  final ValueChanged<DeckTheme> onThemeChanged;

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  PeripheralManager? _peripheral;
  Object? _initError;

  final _clients = <String, ConnectedClient>{};
  final _log = <String>[];
  final _composer = TextEditingController();
  final _subscriptions = <StreamSubscription>[];

  BluetoothLowEnergyState _state = BluetoothLowEnergyState.unknown;
  bool _advertising = false;
  bool _busy = false;
  bool _autoStarted = false;

  /// The service view is a detour from the deck, reached from settings,
  /// rather than a tab competing with it for attention.
  bool _showingService = false;
  int _appCount = 0;

  /// Whether the media keys and key combinations can actually reach macOS.
  /// Re-checked when the window regains focus, since granting it happens in
  /// System Settings rather than here.
  bool _accessibility = true;

  /// App name -> bundle path, filled when the catalogue is built so an icon
  /// request does not have to rescan the disk.
  final _appPaths = <String, String>{};

  /// Serialises the multi-notification transfers. Two of them running at once
  /// would interleave their frames on one characteristic and stall both.
  Future<void> _transfers = Future<void>.value();

  /// Value served on the notify characteristic until real data flows.
  final _notifyCharacteristic = GATTCharacteristic.mutable(
    uuid: BtLink.notifyCharacteristicUuid,
    properties: [
      GATTCharacteristicProperty.read,
      GATTCharacteristicProperty.notify,
    ],
    permissions: [GATTCharacteristicPermission.read],
    descriptors: [],
  );

  final _writeCharacteristic = GATTCharacteristic.mutable(
    uuid: BtLink.writeCharacteristicUuid,
    properties: [
      GATTCharacteristicProperty.write,
      GATTCharacteristicProperty.writeWithoutResponse,
    ],
    permissions: [GATTCharacteristicPermission.write],
    descriptors: [],
  );

  @override
  void initState() {
    super.initState();
    _setUp();
    // Same reason as the client: on Android the advertise button would
    // otherwise be gated on a state only the permission can unlock.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_peripheral != null && _state != BluetoothLowEnergyState.poweredOn) {
        _ensureAuthorized();
      }
      _autoStart();
      _refreshAccessibility();
    });
  }

  /// Brings the service up by itself once the adapter is ready, once per
  /// run. Stopping it manually is respected — this does not restart it.
  void _autoStart() {
    if (_autoStarted || _advertising || _busy) return;
    if (_state != BluetoothLowEnergyState.poweredOn) return;
    _autoStarted = true;
    _toggleAdvertising();
  }

  Future<void> _refreshAccessibility() async {
    final trusted = await MediaControl.trusted;
    if (mounted && trusted != _accessibility) {
      setState(() => _accessibility = trusted);
    }
  }

  /// Returns whether the app may use Bluetooth. Only Android has a runtime
  /// permission to ask for; elsewhere authorization is implied.
  Future<bool> _ensureAuthorized() async {
    final peripheral = _peripheral;
    if (peripheral == null) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await peripheral.authorize();
    } catch (error) {
      _showMessage('$error');
      return false;
    }
  }

  void _setUp() {
    try {
      final peripheral = PeripheralManager();
      _peripheral = peripheral;
      _state = peripheral.state;

      _subscriptions.add(
        peripheral.stateChanged.listen((event) {
          if (!mounted) return;
          setState(() {
            _state = event.state;
            if (event.state != BluetoothLowEnergyState.poweredOn) {
              _advertising = false;
            }
          });
          _autoStart();
        }),
      );

      // Android reports connect/disconnect directly. Apple and the desktop
      // platforms do not, so the streams below are what keeps the list honest
      // there.
      _listenSafely(
        () => peripheral.connectionStateChanged,
        (CentralConnectionStateChangedEventArgs event) {
          if (event.state == ConnectionState.connected) {
            _touch(event.central, 'connected');
          } else {
            _remove(event.central, 'disconnected');
          }
        },
        'connection events',
      );

      _listenSafely(
        () => peripheral.characteristicNotifyStateChanged,
        (GATTCharacteristicNotifyStateChangedEventArgs event) {
          _touch(
            event.central,
            event.state ? 'subscribed' : 'unsubscribed',
            subscribed: event.state,
          );
        },
        'subscription events',
      );

      _listenSafely(
        () => peripheral.characteristicReadRequested,
        (GATTCharacteristicReadRequestedEventArgs event) async {
          _touch(event.central, 'read');
          await peripheral.respondReadRequestWithValue(
            event.request,
            value: const Ack(ok: true, message: 'ready').encode(),
          );
        },
        'read requests',
      );

      _listenSafely(
        () => peripheral.characteristicWriteRequested,
        (GATTCharacteristicWriteRequestedEventArgs event) async {
          // Respond first: the client is blocked on the ATT response, and
          // launching an app takes far longer than the ATT timeout allows.
          await peripheral.respondWriteRequest(event.request);
          await _handleCommand(event.central, event.request.value);
        },
        'write requests',
      );
    } catch (error) {
      _initError = error;
    }
  }

  /// Subscribes to a stream that some platforms refuse to provide, recording
  /// the gap in the log instead of taking the app down.
  void _listenSafely<T>(
    Stream<T> Function() stream,
    void Function(T event) onEvent,
    String label,
  ) {
    try {
      _subscriptions.add(stream().listen(onEvent));
    } on UnsupportedError {
      _log.add('$label are not reported on this platform');
    }
  }

  void _touch(Central central, String activity, {bool? subscribed}) {
    if (!mounted) return;
    final id = central.uuid.toString();
    setState(() {
      final existing = _clients[id];
      _clients[id] =
          existing?.copyWith(subscribed: subscribed, lastActivity: activity) ??
          ConnectedClient(
            central: central,
            since: DateTime.now(),
            subscribed: subscribed ?? false,
            lastActivity: activity,
          );
      _addLog('$activity — ${_short(id)}');
    });
  }

  void _remove(Central central, String activity) {
    if (!mounted) return;
    final id = central.uuid.toString();
    setState(() {
      _clients.remove(id);
      _addLog('$activity — ${_short(id)}');
    });
  }

  void _addLog(String message) {
    // Mirrored to the console so the service can be diagnosed over
    // `flutter run` without reading the window.
    debugPrint('[BTLink] $message');
    final now = TimeOfDay.fromDateTime(DateTime.now());
    _log.insert(
      0,
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}  $message',
    );
    if (_log.length > 50) _log.removeLast();
  }

  Future<void> _handleCommand(Central central, List<int> bytes) async {
    final message = BtMessage.decode(bytes);
    if (message == null) {
      _touch(central, 'unknown command (${bytes.length} bytes)');
      return;
    }
    switch (message) {
      case ListApps():
        _touch(central, 'requested the app list');
        await _queueTransfer(() => _sendCatalogue(central));
      // Every button arrives the same way: a slot number the host resolves
      // against its own layout.
      case PressSlot(:final index):
        await _pressSlot(central, index);
      case RequestLayout():
        _touch(central, 'requested the layout');
        await _queueTransfer(() => _sendLayout(central));
      case RequestIcon(:final name):
        _touch(central, 'icon for $name');
        await _queueTransfer(() => _sendIcon(central, name));
      case DebugText(:final text):
        _touch(central, 'said: $text');
      case Ack() ||
          SetAppearance() ||
          PressSlot() ||
          AppEntry() ||
          ListEnd() ||
          IconUnavailable() ||
          LayoutStart() ||
          LayoutSlot() ||
          LayoutEnd():
        // Host-to-client shapes; a client has no business sending them.
        _touch(central, 'ignored a ${message.runtimeType}');
    }
  }

  /// Streams the installed apps one message at a time. There is no
  /// reassembly on this link, so the catalogue is many small notifications
  /// rather than one large payload.
  /// Runs [work] after every transfer already queued, so a catalogue in
  /// flight finishes before an icon starts.
  Future<void> _queueTransfer(Future<void> Function() work) {
    final completer = Completer<void>();
    _transfers = _transfers.then((_) async {
      try {
        await work();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureAppPaths() async {
    if (_appPaths.isNotEmpty) return;
    final apps = await AppLauncher.list();
    _appPaths.addEntries(apps.map((app) => MapEntry(app.name, app.path)));
    if (mounted) setState(() => _appCount = apps.length);
  }

  Future<void> _sendCatalogue(Central central) async {
    final apps = await AppLauncher.list();
    _appPaths
      ..clear()
      ..addEntries(apps.map((app) => MapEntry(app.name, app.path)));
    if (mounted) setState(() => _appCount = apps.length);
    for (final app in apps) {
      await _send(central, AppEntry(name: app.name, category: app.category));
      // Notifications queue in the controller and are silently dropped once
      // it fills; pacing them is cheaper than detecting the loss.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _send(central, ListEnd(count: apps.length));
    if (mounted) {
      setState(() => _addLog('sent ${apps.length} apps to ${_short(
        central.uuid.toString(),
      )}'));
    }
  }

  /// Acts on the button in [index], whatever the host's own layout says is
  /// there. The client sent only a number, so a shell command cannot be
  /// injected from the other end of the link.
  Future<void> _pressSlot(Central central, int index) async {
    final layout = await LayoutStore.load();
    if (index < 0 || index >= layout.slots.length) {
      _touch(central, 'slot $index is outside the layout');
      await _send(central, const Ack(ok: false, message: 'No such button'));
      return;
    }
    final stored = layout.slots[index];
    final item = stored == null ? null : DeckItem.parse(stored);
    if (item == null) {
      _touch(central, 'slot $index is empty');
      await _send(central, const Ack(ok: false, message: 'Empty button'));
      return;
    }

    // Names the slot as well as what was in it: the client sends only a
    // number, and the log should not read as though it sent the action.
    _touch(central, 'slot $index -> ${item.label}');
    final result = switch (item) {
      AppItem(:final name) => await AppLauncher.open(name),
      ActionItem(:final action) => await MediaControl.run(action),
      ShellItem(:final command) => await CommandRunner.shell(command),
      ShortcutItem(:final name) => await CommandRunner.shortcut(name),
      KeyComboItem() => await CommandRunner.keyCombo(
        modifiers: item.modifiers,
        key: item.key,
        special: item.special,
        label: item.combination,
      ),
    };
    if (mounted) setState(() => _addLog(result.message));
    await _send(central, Ack(ok: result.ok, message: result.message));
  }

  /// Streams the layout: a header, one message per occupied cell, then an
  /// end marker. Empty cells are not sent — the header's dimensions are
  /// enough to place the rest.
  Future<void> _sendLayout(Central central) async {
    final layout = await LayoutStore.load();
    await _send(
      central,
      LayoutStart(
        columns: layout.columns,
        rows: layout.rows,
        pages: layout.pages,
      ),
    );
    for (var index = 0; index < layout.slots.length; index++) {
      final value = layout.slots[index];
      if (value == null) continue;
      await _send(central, LayoutSlot(index: index, value: value));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _send(central, const LayoutEnd());
    // The appearance rides along with the layout so a fresh client is
    // dressed correctly before it draws anything.
    final appearance = await SettingsStore.load();
    await _send(
      central,
      SetAppearance(
        theme: appearance.theme,
        showLabels: appearance.showLabels,
      ),
    );
    if (mounted) {
      setState(() {
        _addLog(
          'sent layout ${layout.columns}x${layout.rows}'
          '${layout.pages > 1 ? ' x${layout.pages} pages' : ''} to '
          '${_short(central.uuid.toString())}',
        );
      });
    }
  }

  /// Pushes the appearance to everyone subscribed, so the phone follows the
  /// Mac the moment it is changed here.
  Future<void> _broadcastAppearance(DeckTheme theme, bool showLabels) async {
    final message = SetAppearance(theme: theme, showLabels: showLabels);
    for (final client in _clients.values.where((c) => c.subscribed)) {
      await _queueTransfer(() => _send(client.central, message));
    }
  }

  /// Pushes an edited layout to everyone currently subscribed, so the deck
  /// on the phone changes as the grid is arranged here.
  Future<void> _broadcastLayout(DeckLayout layout) async {
    for (final client in _clients.values.where((c) => c.subscribed)) {
      await _queueTransfer(() => _sendLayout(client.central));
    }
  }

  /// Renders an app's icon and streams it as binary frames sized to the
  /// link's MTU.
  Future<void> _sendIcon(Central central, String appName) async {
    final peripheral = _peripheral;
    if (peripheral == null) return;

    // The client restores its deck from local storage and can ask for an
    // icon before it has asked for the catalogue.
    await _ensureAppPaths();
    final path = _appPaths[appName];
    final png = path == null
        ? null
        : await AppLauncher.icon(path, size: BtLink.iconSize);
    if (png == null) {
      await _send(central, IconUnavailable(name: appName));
      return;
    }

    final int maximum;
    try {
      maximum = await peripheral.getMaximumNotifyLength(central);
    } catch (error) {
      if (mounted) setState(() => _addLog('icon aborted: $error'));
      return;
    }

    final capacity = IconFrame.payloadCapacity(maximum, appName);
    if (capacity <= 0) {
      // A name long enough to fill the MTU on its own leaves nowhere to put
      // the image.
      await _send(central, IconUnavailable(name: appName));
      return;
    }

    final total = (png.length / capacity).ceil();
    for (var index = 0; index < total; index++) {
      final start = index * capacity;
      final end = start + capacity < png.length ? start + capacity : png.length;
      try {
        await peripheral.notifyCharacteristic(
          central,
          _notifyCharacteristic,
          value: IconFrame.encode(
            name: appName,
            index: index,
            total: total,
            payload: png.sublist(start, end),
          ),
        );
      } catch (error) {
        if (mounted) setState(() => _addLog('icon frame failed: $error'));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    if (mounted) {
      setState(() {
        _addLog('sent $appName icon (${png.length}B in $total frames)');
      });
    }
  }

  /// Sends one message, refusing anything the negotiated MTU cannot carry.
  Future<void> _send(Central central, BtMessage message) async {
    final peripheral = _peripheral;
    if (peripheral == null) return;
    final value = message.encode();
    try {
      final maximum = await peripheral.getMaximumNotifyLength(central);
      if (value.length > maximum) {
        if (mounted) {
          setState(() {
            _addLog('dropped ${value.length}B message, MTU allows $maximum');
          });
        }
        return;
      }
      await peripheral.notifyCharacteristic(
        central,
        _notifyCharacteristic,
        value: value,
      );
    } catch (error) {
      if (mounted) setState(() => _addLog('notify failed: $error'));
    }
  }

  /// Pushes a value on the notify characteristic to every subscribed client.
  /// Centrals that never subscribed are skipped by the platform anyway.
  Future<void> _broadcast() async {
    final text = _composer.text.trim();
    if (_peripheral == null || text.isEmpty) return;

    final targets = _clients.values.where((c) => c.subscribed).toList();
    if (targets.isEmpty) {
      _showMessage('No subscribed client to notify.');
      return;
    }

    for (final client in targets) {
      await _send(client.central, DebugText(text: text));
    }
    final delivered = targets.length;

    if (!mounted) return;
    setState(() {
      _addLog('sent "$text" to $delivered client(s)');
      _composer.clear();
    });
  }

  String _short(String uuid) =>
      uuid.length > 8 ? '${uuid.substring(0, 8)}…' : uuid;

  Future<void> _toggleAdvertising() async {
    final peripheral = _peripheral;
    if (peripheral == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_advertising) {
        await peripheral.stopAdvertising();
        await peripheral.removeAllServices();
        if (mounted) {
          setState(() {
            _advertising = false;
            _clients.clear();
            _addLog('stopped advertising');
          });
        }
        return;
      }

      if (_state == BluetoothLowEnergyState.poweredOff) {
        _showMessage('Turn Bluetooth on first.');
        return;
      }
      if (!await _ensureAuthorized()) {
        _showMessage('Bluetooth permission denied.');
        return;
      }

      // A service can only be published once, so clear anything left over
      // from a previous run before re-adding.
      await peripheral.removeAllServices();
      await peripheral.addService(
        GATTService(
          uuid: BtLink.serviceUuid,
          isPrimary: true,
          includedServices: [],
          characteristics: [_notifyCharacteristic, _writeCharacteristic],
        ),
      );
      await peripheral.startAdvertising(
        Advertisement(
          name: BtLink.advertisedName,
          serviceUUIDs: [BtLink.serviceUuid],
        ),
      );
      if (mounted) {
        setState(() {
          _advertising = true;
          _addLog('advertising as ${BtLink.advertisedName}');
        });
      }
    } catch (error) {
      _showMessage('$error');
      if (mounted) setState(() => _advertising = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _composer.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_advertising) _peripheral?.stopAdvertising();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return UnsupportedPage(details: '$_initError');
    }

    final clients = _clients.values.toList()
      ..sort((a, b) => a.since.compareTo(b.since));
    final subscribedCount = clients.where((c) => c.subscribed).length;

    if (_showingService) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Service'),
          leading: IconButton(
            tooltip: 'Back to the deck',
            onPressed: () => setState(() => _showingService = false),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: _serviceTab(context, clients, subscribedCount),
      );
    }

    // The window is the deck. Everything else — grid size, appearance, the
    // service details — lives behind the gear.
    return Scaffold(
      body: LayoutPage(
        onChanged: _broadcastLayout,
        onAppearanceChanged: (theme, showLabels) {
          widget.onThemeChanged(theme);
          _broadcastAppearance(theme, showLabels);
        },
        onShowService: () => setState(() => _showingService = true),
      ),
    );
  }

  Widget _serviceTab(
    BuildContext context,
    List<ConnectedClient> clients,
    int subscribedCount,
  ) {
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_accessibility)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Accessibility is not granted'),
                subtitle: const Text(
                  'Media keys and key combinations will do nothing until '
                  'this app is allowed in System Settings',
                ),
                trailing: FilledButton(
                  onPressed: () async {
                    await MediaControl.requestTrust();
                    await _refreshAccessibility();
                  },
                  child: const Text('Grant'),
                ),
              ),
            ),
          _StatusCard(
            state: _state,
            appCount: _appCount,
            advertising: _advertising,
            busy: _busy,
            onToggle: _state == BluetoothLowEnergyState.unsupported
                ? null
                : _toggleAdvertising,
          ),
          const SizedBox(height: 24),
          Text(
            'Connected clients (${clients.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (clients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No client has connected yet.'),
              ),
            )
          else
            ...clients.map((client) => _ClientTile(client: client)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  enabled: subscribedCount > 0,
                  onSubmitted: (_) => _broadcast(),
                  decoration: InputDecoration(
                    hintText: subscribedCount > 0
                        ? 'Notify $subscribedCount subscribed client(s)'
                        : 'No subscribed client yet',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: subscribedCount > 0 ? _broadcast : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_log.isEmpty)
            const Text('Nothing yet.')
          else
            ..._log.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.appCount,
    required this.advertising,
    required this.busy,
    required this.onToggle,
  });

  final BluetoothLowEnergyState state;
  final int appCount;
  final bool advertising;
  final bool busy;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  advertising ? Icons.wifi_tethering : Icons.portable_wifi_off,
                  color: advertising ? Colors.green : theme.disabledColor,
                ),
                const SizedBox(width: 12),
                Text(
                  advertising ? 'Advertising' : 'Idle',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Adapter', state.name),
            _row('Local name', BtLink.advertisedName),
            _row('Service', BtLink.serviceUuid.toString()),
            _row(
              'Apps',
              AppLauncher.supported
                  ? (appCount == 0 ? 'not requested yet' : '$appCount found')
                  : 'launching unsupported on this platform',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onToggle,
                icon: Icon(advertising ? Icons.stop : Icons.play_arrow),
                label: Text(
                  advertising ? 'Stop advertising' : 'Start advertising',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client});

  final ConnectedClient client;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: client.subscribed
              ? Colors.green.withValues(alpha: 0.15)
              : Theme.of(context).disabledColor.withValues(alpha: 0.15),
          child: Icon(
            client.subscribed ? Icons.notifications_active : Icons.link,
            color: client.subscribed ? Colors.green : null,
          ),
        ),
        title: Text(client.id, style: const TextStyle(fontSize: 13)),
        subtitle: Text(client.lastActivity),
      ),
    );
  }
}
